import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/download_repository.dart';
import 'package:kartka/downloads/downloads_snapshot.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/engine/watch_value.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_index.dart';
import 'package:kartka/downloads/queue/download_queue.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/platform.dart';

/// The local [DownloadRepository]: a persistent queue over [DownloadEngine].
///
/// Queue and index live in [KeyValueStore], pages in [BlobStore]. On Android
/// downloads run only while the app process is alive (foreground); there is
/// no WorkManager/background worker in v1 — on the next start [start]
/// resumes whatever was queued or interrupted.
class DownloadService implements DownloadRepository, DownloadedLookup {
  /// Creates the service; call [start] once to resume persisted work.
  new({
    required this.kv,
    required this.blobs,
    required this.engine,
    this.maxChapters = 2,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Queue and index storage.
  final KeyValueStore kv;

  /// Page storage.
  final BlobStore blobs;

  /// Downloads one chapter at a time per call.
  final DownloadEngine engine;

  /// Chapters downloading at once (pages are further capped per host).
  final int maxChapters;

  final DateTime Function() _now;
  late final Future<void> _ready = _load();
  late DownloadQueue _queue;
  late DownloadIndex _index;
  final _changes = StreamController<void>.broadcast(sync: true);
  final Map<String, _Run> _running = {};

  Future<void> _load() async {
    _queue = DownloadQueue.decode(await kv.get(queueKvKey));
    _index = DownloadIndex.decode(await kv.get(indexKvKey));
  }

  /// Loads the persisted queue and resumes it (unless paused).
  Future<void> start() async {
    await _ready;
    _pump();
  }

  @override
  Future<void> enqueue(MangaKey key, ChapterInfo chapter) async {
    await _ready;
    if (_index.chapter(key, chapter.url) != null) return;
    final task = DownloadTask(
      mangaKey: key,
      chapter: chapter,
      enqueuedAt: _now(),
    );
    if (_queue.add(task)) await _changed();
  }

  @override
  Stream<DownloadState> watch(MangaKey key, String chapterUrl) =>
      _watch(() => _stateOf(key, chapterUrl)).distinct();

  @override
  Stream<bool> hasDownloads(MangaKey key) =>
      _watch(() => _index.chapters(key).isNotEmpty).distinct();

  /// Queue, pause flag and offline index, re-emitted on every change.
  Stream<DownloadsSnapshot> watchAll() => _watch(
    () => DownloadsSnapshot(
      paused: _queue.paused,
      queue: _queue.tasks,
      index: _index,
    ),
  );

  @override
  Future<List<PageRef>?> offlinePages(MangaKey key, String chapterUrl) async {
    await _ready;
    final record = _index.chapter(key, chapterUrl);
    if (record == null) return null;
    return [
      for (var i = 0; i < record.pageCount; i++)
        PageRef(
          index: i,
          imageUrl: blobPageUrl(pageBlobKey(key, chapterUrl, i)),
        ),
    ];
  }

  /// Stops starting pages; running pages finish, chapters go back to queued.
  Future<void> pause() => _setPaused(paused: true);

  /// Resumes the queue.
  Future<void> resume() => _setPaused(paused: false);

  /// Requeues a failed chapter.
  Future<void> retry(MangaKey key, String chapterUrl) async {
    await _ready;
    final task = _queue.byId(taskId(key, chapterUrl));
    if (task != null && _queue.add(task)) await _changed();
  }

  /// Drops a chapter from the queue and deletes its partial pages.
  Future<void> cancel(MangaKey key, String chapterUrl) async {
    await _ready;
    final id = taskId(key, chapterUrl);
    final run = _running[id];
    if (run != null) {
      run.cancelled = true; // the runner removes it once the page stops
    } else if (_queue.remove(id) != null) {
      await _deleteBlobs(key, chapterUrl);
      await _changed();
    }
  }

  /// Deletes one offline chapter.
  Future<void> deleteChapter(MangaKey key, String chapterUrl) async {
    await _ready;
    if (_index.removeChapter(key, chapterUrl) == null) return;
    await _deleteBlobs(key, chapterUrl);
    await _changed();
  }

  /// Deletes every offline chapter of [key] and cancels its queued ones.
  Future<void> deleteManga(MangaKey key) async {
    await _ready;
    for (final t in _queue.tasks.where((t) => t.mangaKey == key)) {
      await cancel(key, t.chapter.url);
    }
    for (final c in _index.removeManga(key)) {
      await _deleteBlobs(key, c.chapterUrl);
    }
    await _changed();
  }

  DownloadState _stateOf(MangaKey key, String chapterUrl) {
    final record = _index.chapter(key, chapterUrl);
    if (record != null) {
      return DownloadState(
        status: DownloadStatus.done,
        pagesDone: record.pageCount,
        pagesTotal: record.pageCount,
      );
    }
    return _queue.byId(taskId(key, chapterUrl))?.state ?? DownloadState.none;
  }

  Stream<T> _watch<T>(T Function() read) =>
      watchValue(_ready, _changes.stream, read);

  Future<void> _setPaused({required bool paused}) async {
    await _ready;
    _queue.paused = paused;
    await _changed();
  }

  /// Persists, notifies and lets the queue advance.
  Future<void> _changed() async {
    _changes.add(null);
    _pump();
    await kv.set(queueKvKey, _queue.encode());
    await kv.set(indexKvKey, _index.encode());
  }

  Future<void> _deleteBlobs(MangaKey key, String chapterUrl) async {
    for (final k in await blobs.list(chapterBlobPrefix(key, chapterUrl))) {
      await blobs.delete(k);
    }
  }

  void _pump() {
    for (final task in _queue.runnable()) {
      if (_running.length >= maxChapters) return;
      unawaited(_run(task));
    }
  }

  Future<void> _run(DownloadTask task) async {
    final run = _running[task.id] = _Run();
    void update(DownloadState s) {
      _queue.update(task.id, s);
      _changes.add(null);
    }

    update(
      DownloadState(
        status: DownloadStatus.downloading,
        pagesDone: task.state.pagesDone,
        pagesTotal: task.state.pagesTotal,
      ),
    );
    try {
      final record = await engine.download(
        task,
        onProgress: update,
        shouldStop: () => run.cancelled || _queue.paused,
      );
      _queue.remove(task.id);
      if (run.cancelled) {
        await _deleteBlobs(task.mangaKey, task.chapter.url);
      } else {
        _index.put(task.mangaKey, record);
      }
    } on DownloadStopped {
      if (run.cancelled) {
        _queue.remove(task.id);
        await _deleteBlobs(task.mangaKey, task.chapter.url);
      } else {
        final s = _queue.byId(task.id)!.state;
        update(
          DownloadState(
            status: DownloadStatus.queued,
            pagesDone: s.pagesDone,
            pagesTotal: s.pagesTotal,
          ),
        );
      }
    } on Object catch (e) {
      final s = _queue.byId(task.id)!.state;
      update(
        DownloadState(
          status: DownloadStatus.failed,
          pagesDone: s.pagesDone,
          pagesTotal: s.pagesTotal,
          error: '$e',
        ),
      );
    }
    _running.remove(task.id);
    await _changed();
  }
}

class _Run {
  bool cancelled = false;
}
