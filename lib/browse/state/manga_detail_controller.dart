import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// No registered source has the route's source id (not installed, server
/// unreachable, or an id kartka has no source for, e.g. `sy-builtin:*`).
class SourceUnavailable implements Exception {
  /// Creates the error for [sourceId].
  const new(this.sourceId);

  /// The missing source id.
  final String sourceId;

  @override
  String toString() => 'Source $sourceId is not available';
}

/// State and actions of the manga detail screen.
class MangaDetailController extends ChangeNotifier {
  /// Creates a controller for the manga at [mangaUrl] in [sourceId].
  new(
    this._deps, {
    required this.sourceId,
    required this.mangaUrl,
    this.sourceWait = const Duration(seconds: 10),
  }) : key = mangaKeyOf(sourceId, mangaUrl);

  final BrowseDeps _deps;

  /// Source id from the route.
  final String sourceId;

  /// Manga url from the route.
  final String mangaUrl;

  /// The manga's key.
  final MangaKey key;

  /// How long to wait for a runtime source (Suwayomi, plugin) to appear.
  final Duration sourceWait;

  /// Loaded details; null while loading or after a failure.
  MangaDetails? details;

  /// Chapters oldest-first.
  List<ChapterInfo> chapters = const [];

  /// Failure of the last [load].
  Object? error;

  /// Whether a [load] is in flight.
  bool loading = false;
  bool _disposed = false;

  /// Loads details and a fresh chapter list in parallel. After a
  /// [SourceUnavailable] (the Retry button) it first asks every provider to
  /// re-list its sources, so a server that was down at start is seen again.
  Future<void> load() async {
    if (error is SourceUnavailable) unawaited(_deps.sources.refresh());
    loading = true;
    error = null;
    _notify();
    try {
      final source = await _source();
      final results = await Future.wait<Object>([
        source.details(mangaUrl),
        _deps.chapters.load(key, refresh: true),
      ]);
      details = results[0] as MangaDetails;
      chapters = readingOrder(results[1] as List<ChapterInfo>);
    } on Object catch (e) {
      error = e;
    }
    loading = false;
    _notify();
  }

  /// [load] again, reporting what changed against the chapters shown
  /// before it (none are new when no list was shown, e.g. after a failed
  /// first load). A failure is logged to the diagnostics log as
  /// `details.refresh` with the source id only: no URL, no query string.
  Future<RefreshOutcome> refresh() async {
    final shown = details != null;
    final before = {for (final c in chapters) c.url};
    await load();
    final failure = error;
    if (failure == null) {
      return RefreshSucceeded([
        for (final c in chapters)
          if (shown && !before.contains(c.url)) c,
      ]);
    }
    await _deps.diagnostics?.append(
      DiagnosticEntry.failure(
        at: _deps.clock(),
        kind: 'details.refresh',
        error: stripUrls('$failure'),
        sourceId: sourceId,
      ),
    );
    return RefreshFailed(failure);
  }

  /// The route's source, waiting up to [sourceWait] for a runtime source.
  /// Completes without awaiting the subscription's cancel, so a slow
  /// provider teardown never delays the screen.
  Future<MangaSource> _source() {
    final found = Completer<MangaSource>();
    late final StreamSubscription<void> sub;
    final timer = Timer(sourceWait, () {
      if (found.isCompleted) return;
      found.completeError(SourceUnavailable(sourceId));
      unawaited(sub.cancel());
    });
    sub = _deps.sources.watch().listen((_) {
      final source = _deps.sources.byId(sourceId);
      if (source == null || found.isCompleted) return;
      timer.cancel();
      found.complete(source);
      unawaited(sub.cancel());
    });
    return found.future;
  }

  /// Whether the manga is in the library, live.
  Stream<bool> inLibrary() => _deps.library
      .watch()
      .map((entries) => entries.any((e) => e.key == key))
      .distinct();

  /// Read marks + progress, live; feed to `readUrls` with [chapters].
  Stream<ReadMarks> readMarks() => watchReadMarks(_deps.progress, key);

  /// Reading progress, live (drives "Continue").
  Stream<ReadingProgress?> progress() => _deps.progress.watch(key);

  /// Adds the manga to (or removes it from) the library.
  Future<void> setInLibrary({required bool add}) async {
    final d = details;
    if (!add) {
      await _deps.library.remove(key);
      return;
    }
    if (d == null) return;
    final now = _deps.clock();
    await _deps.library.upsert(
      LibraryEntry(
        key: key,
        sourceId: sourceId,
        mangaUrl: mangaUrl,
        title: d.title,
        coverUrl: d.coverUrl,
        addedAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Marks [chapter] read or unread.
  Future<void> setRead(ChapterInfo chapter, {required bool read}) => read
      ? _deps.progress.markRead(key, chapter.url)
      : _deps.progress.markUnread(key, chapter.url);

  /// Queues [toDownload] (no-op without a downloads part).
  Future<void> download(Iterable<ChapterInfo> toDownload) async {
    final downloads = _deps.downloads;
    if (downloads == null) return;
    for (final c in toDownload) {
      await downloads.enqueue(key, c);
    }
  }

  /// Live download state of [chapterUrl]; null without a downloads part.
  Stream<DownloadState>? downloadState(String chapterUrl) =>
      _deps.downloads?.watch(key, chapterUrl);

  /// Whether queued chapters can be cancelled and downloaded ones deleted.
  bool get canManageDownloads => _deps.downloadService != null;

  /// Drops [chapter] from the download queue (no-op without the service).
  Future<void> cancelDownload(ChapterInfo chapter) async {
    await _deps.downloadService?.cancel(key, chapter.url);
  }

  /// Deletes [chapter]'s offline pages (no-op without the service).
  Future<void> deleteDownload(ChapterInfo chapter) async {
    await _deps.downloadService?.deleteChapter(key, chapter.url);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
