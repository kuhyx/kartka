import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/detail_store.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/browse/state/source_wait.dart';
import 'package:kartka/browse/state/stored_detail.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';

export 'package:kartka/browse/state/source_wait.dart' show SourceUnavailable;

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
  /// A failure is logged as `details.load` (source id only, URLs stripped).
  ///
  /// Stale-while-revalidate: with nothing shown yet, a library entry (and
  /// the stored chapter list) is shown at once while the network runs, so a
  /// reopen never waits on the source. A failed refresh keeps it, in [error].
  Future<void> load() async {
    await _load();
    final failure = error;
    if (failure != null) await _log('details.load', failure, _stack);
  }

  StackTrace? _stack;

  Future<void> _log(String kind, Object failure, [StackTrace? stack]) async =>
      await _deps.diagnostics?.append(
        DiagnosticEntry.failure(
          at: _deps.clock(),
          kind: kind,
          error: stripUrls('$failure'),
          stack: stack == null
              ? null
              : StackTrace.fromString(stripUrls('$stack')),
          sourceId: sourceId,
        ),
      );

  Future<void> _load() async {
    if (error is SourceUnavailable) unawaited(_deps.sources.refresh());
    loading = true;
    error = null;
    _notify();
    // Started before the seed: the seed must never delay the network.
    final fresh = _fetch()..ignore();
    if (details == null) await _seed();
    try {
      final (d, list) = await fresh;
      final shownCover = details?.coverUrl;
      details = shownCover == null ? d : withCover(d, shownCover);
      _keep(d).ignore(); // A cache: a failed write only costs the next open.
      chapters = readingOrder(list);
    } on Object catch (e, stack) {
      error = e;
      _stack = stack;
    }
    loading = false;
    _notify();
  }

  Future<(MangaDetails, List<ChapterInfo>)> _fetch() async {
    final source = await waitForSource(_deps.sources, sourceId, sourceWait);
    final results = await Future.wait<Object>([
      source.details(mangaUrl),
      _deps.chapters.load(key, refresh: true),
    ]);
    return (results[0] as MangaDetails, results[1] as List<ChapterInfo>);
  }

  /// Stores [d] for the next open when the manga is in the library.
  Future<void> _keep(MangaDetails d) async {
    if (await libraryEntry(_deps.library, key) != null) {
      await _deps.details.write(key, d);
    }
  }

  /// Shows the library entry and stored chapters, when there is an entry.
  Future<void> _seed() async {
    final stored = await storedDetail(_deps, key);
    if (stored == null) return;
    details = stored.$1;
    chapters = readingOrder(stored.$2);
    _notify();
  }

  /// Re-fetches the chapter list through the shared checker
  /// (`BrowseDeps.updates`), which diffs it against the stored list and
  /// persists it; details stay as loaded. With no fresh details shown (a
  /// failed first load, or stored data behind a failed load) it reloads
  /// instead, reporting the chapters not shown before it. Any failure,
  /// that reload's included, is logged once, as `details.refresh` (never
  /// also `details.load`), with the source id only and URLs stripped.
  Future<RefreshOutcome> refresh() async {
    if (details == null || error != null) return await _reload();
    switch (await _deps.updates.check(key)) {
      case UpdateFound(:final chapters, :final added):
        this.chapters = readingOrder(chapters);
        _notify();
        return RefreshSucceeded(added);
      case UpdateFailed(:final error, :final stack):
        return await _failed(error, stack);
    }
  }

  Future<RefreshOutcome> _reload() async {
    final shown = {for (final c in chapters) c.url};
    await _load();
    final failure = error;
    if (failure != null) return await _failed(failure, _stack);
    return RefreshSucceeded([
      if (shown.isNotEmpty)
        for (final c in chapters)
          if (!shown.contains(c.url)) c,
    ]);
  }

  Future<RefreshOutcome> _failed(Object failure, StackTrace? stack) async {
    await _log('details.refresh', failure, stack);
    return RefreshFailed(failure);
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
      await _deps.details.remove(key);
      return;
    }
    if (d == null) return;
    await _deps.details.write(key, d);
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
