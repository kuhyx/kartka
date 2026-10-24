import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/downloads/engine/host_limiter.dart';
import 'package:kartka/downloads/engine/retry.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_index.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/platform/platform.dart';

/// Fetches the bytes of one page (normally `PageImageLoader.load`).
typedef PageLoader = Future<Uint8List> Function(PageRef page);

/// Finds the source serving `sourceId`, or `null` when none is installed.
typedef SourceLookup = MangaSource? Function(String sourceId);

/// Thrown inside a download when it was paused or cancelled.
class DownloadStopped implements Exception {
  /// Creates the signal.
  const DownloadStopped();
}

/// Whether a failed page is worth another attempt: network errors, 408,
/// 429 and 5xx are; other 4xx and a stop request are not.
bool isRetryable(Object error) {
  if (error is DownloadStopped) return false;
  if (error is KartkaHttpException) {
    final s = error.statusCode;
    return s == 408 || s == 429 || s >= 500;
  }
  return true;
}

/// Downloads one chapter into [BlobStore], page by page.
///
/// Requests are capped per host by [limiter] (the page-list call counts
/// against `source:<id>`), and each one is retried per [policy].
class DownloadEngine {
  /// Creates an engine.
  DownloadEngine({
    required this.blobs,
    required this.loadPage,
    required this.sourceFor,
    HostLimiter? limiter,
    this.policy = const RetryPolicy(),
    this.sleep,
    DateTime Function()? now,
  }) : limiter = limiter ?? HostLimiter(),
       _now = now ?? DateTime.now;

  /// Where pages go.
  final BlobStore blobs;

  /// How page bytes are fetched.
  final PageLoader loadPage;

  /// Resolves a task's source.
  final SourceLookup sourceFor;

  /// Per-host concurrency cap shared by every running chapter.
  final HostLimiter limiter;

  /// Retry policy for the page list and each page.
  final RetryPolicy policy;

  /// Backoff sleep; `null` waits for real.
  final Sleep? sleep;

  final DateTime Function() _now;

  /// Downloads [task]'s chapter. Pages already in [blobs] (an interrupted
  /// earlier run) are kept. Throws [DownloadStopped] when [shouldStop]
  /// turns true before a page starts, or the last error of a page.
  Future<OfflineChapter> download(
    DownloadTask task, {
    required void Function(DownloadState state) onProgress,
    bool Function() shouldStop = _never,
  }) async {
    final source = sourceFor(task.sourceId);
    if (source == null) throw StateError('source ${task.sourceId} missing');
    final url = task.chapter.url;
    final pages = await _guarded(
      'source:${task.sourceId}',
      shouldStop,
      () => source.pages(url),
    );
    if (pages.isEmpty) throw StateError('chapter $url has no pages');
    final stored = (await blobs.list(chapterBlobPrefix(task.mangaKey, url)))
        .toSet();
    var done = 0;
    var bytes = 0;
    void report() => onProgress(
      DownloadState(
        status: DownloadStatus.downloading,
        pagesDone: done,
        pagesTotal: pages.length,
      ),
    );
    report();
    await Future.wait([
      for (final page in pages)
        _page(task, page, stored, shouldStop).then((size) {
          bytes += size;
          done++;
          report();
        }),
    ]);
    return OfflineChapter(
      chapterUrl: url,
      chapterName: task.chapter.name,
      pageCount: pages.length,
      bytes: bytes,
      downloadedAt: _now(),
    );
  }

  /// Stores one page unless already stored; returns its size in bytes.
  Future<int> _page(
    DownloadTask task,
    PageRef page,
    Set<String> stored,
    bool Function() shouldStop,
  ) async {
    final key = pageBlobKey(task.mangaKey, task.chapter.url, page.index);
    final existing = stored.contains(key) ? await blobs.get(key) : null;
    if (existing != null) return existing.length;
    final data = await _guarded(
      hostOf(page.imageUrl),
      shouldStop,
      () => loadPage(page),
    );
    await blobs.put(key, data);
    return data.length;
  }

  Future<T> _guarded<T>(
    String host,
    bool Function() shouldStop,
    Future<T> Function() job,
  ) {
    Future<T> attempt() => limiter.run(host, () {
      if (shouldStop()) throw const DownloadStopped();
      return job();
    });
    final s = sleep;
    return s == null
        ? retry(attempt, policy: policy, shouldRetry: isRetryable)
        : retry(attempt, policy: policy, shouldRetry: isRetryable, sleep: s);
  }
}

bool _never() => false;
