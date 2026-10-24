import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

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

  /// Loads details and a fresh chapter list in parallel.
  Future<void> load() async {
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

  Future<MangaSource> _source() async {
    final now = _deps.sources.byId(sourceId);
    if (now != null) return now;
    try {
      await _deps.sources
          .watch()
          .firstWhere((_) => _deps.sources.byId(sourceId) != null)
          .timeout(sourceWait);
    } on TimeoutException {
      throw StateError('Source $sourceId is not available');
    }
    return _deps.sources.byId(sourceId)!;
  }

  /// Whether the manga is in the library, live.
  Stream<bool> inLibrary() => _deps.library
      .watch()
      .map((entries) => entries.any((e) => e.key == key))
      .distinct();

  /// Read chapter urls, live.
  Stream<Set<String>> readChapters() => _deps.progress.readChapters(key);

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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
