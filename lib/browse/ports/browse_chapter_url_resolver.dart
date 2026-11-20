import 'dart:async';
import 'dart:collection';

import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';

/// Tracking's `ChapterUrlResolver` port: chapter number → chapter url.
///
/// A list not stored on this device is fetched at most [maxFetches] at a
/// time. Tracking follows every binding at start, and on a cold device
/// each one asked at once: 370 chapter lists plus their manga-id lookups
/// went out together, filled the browser's 6 connections to the wrapper,
/// and every other request (the migration walk's source list, a reader
/// page) waited behind them for minutes. A stored list never waits.
class BrowseChapterUrlResolver {
  /// Creates the port over `store`.
  new(this._store);

  final ChapterStore _store;

  /// Chapter-list fetches in flight at most.
  static const maxFetches = 2;

  int _fetching = 0;
  final _waiting = Queue<Completer<void>>();

  Future<List<ChapterInfo>> _load(MangaKey key) async {
    if (await _store.stored(key) case final hit?) return hit;
    if (_fetching >= maxFetches) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _fetching++;
    }
    try {
      return await _store.load(key);
    } finally {
      // Hand the slot straight to the next waiter (the count stays).
      if (_waiting.isEmpty) {
        _fetching--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }

  /// Url of the chapter numbered [chapterNumber] in [key] (the oldest one
  /// when several releases share the number), or null when there is none or
  /// the chapters cannot be loaded.
  Future<String?> resolve(MangaKey key, int chapterNumber) async {
    final List<ChapterInfo> chapters;
    try {
      chapters = await _load(key);
    } on Object {
      return null;
    }
    for (final c in readingOrder(chapters)) {
      if (c.number == chapterNumber) return c.url;
    }
    return null;
  }

  /// Number of the chapter at [chapterUrl] in [key], or null when the
  /// chapter is unknown, unnumbered, or the chapters cannot be loaded.
  Future<double?> numberOf(MangaKey key, String chapterUrl) async {
    final List<ChapterInfo> chapters;
    try {
      chapters = await _load(key);
    } on Object {
      return null;
    }
    for (final c in chapters) {
      if (c.url == chapterUrl) return c.number;
    }
    return null;
  }
}
