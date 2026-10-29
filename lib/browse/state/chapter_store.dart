import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kartka/browse/state/chapter_list_decoder.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Finds the source for a source id (normally `SourceRegistry.byId`).
typedef SourceLookup = MangaSource? Function(String sourceId);

/// Told the chapters (oldest first, never empty) a fetch added to a list
/// that was stored before (`ChapterAdditionSink`).
typedef ChaptersAdded = void Function(MangaKey key, List<ChapterInfo> added);

/// Chapter lists per manga, fetched from the owning source and cached so the
/// library (unread counts) and tracking (chapter-number → url) can answer
/// without a network call per row.
class ChapterStore {
  /// Creates a store resolving sources through `lookup`; with a `kv` store,
  /// lists survive restarts (library unread counts show before a re-fetch).
  /// `onAdded` hears every fetch that grows a stored list, whichever caller
  /// fetched; a first fetch is a baseline and is not reported.
  new(this._lookup, {this._kv, this._onAdded});

  final SourceLookup _lookup;
  final KeyValueStore? _kv;
  final ChaptersAdded? _onAdded;
  final Map<MangaKey, List<ChapterInfo>> _cache = {};
  final _decoder = ChapterListDecoder();
  // Per key, so a load tells only that key's watchers: one shared stream
  // filtered by every watcher made N restores at cold start cost N².
  final _watchers = <MangaKey, Set<StreamController<List<ChapterInfo>?>>>{};

  /// Watcher callbacks run so far (the startup-cost tests bound it).
  @visibleForTesting
  int callbacks = 0;

  void _changed(MangaKey key) {
    final watchers = _watchers[key];
    if (watchers == null) return;
    for (final out in [...watchers]) {
      callbacks++;
      out.add(_cache[key]);
    }
  }

  /// Cached chapters of [key] (source order), or null when never loaded.
  List<ChapterInfo>? cached(MangaKey key) => _cache[key];

  /// Chapters of [key]: the cache unless [refresh] or nothing is cached, in
  /// which case they are fetched and cached. Throws [StateError] when the
  /// key's source is not registered.
  Future<List<ChapterInfo>> load(MangaKey key, {bool refresh = false}) async {
    if (!refresh) {
      final hit = _cache[key] ?? await _restore(key);
      if (hit != null) return hit;
    }
    final (sourceId, url) = splitMangaKey(key);
    final source = _lookup(sourceId);
    if (source == null) throw StateError('Unknown source $sourceId');
    // The prior list, from the kv copy too: after a restart the cache is
    // empty, and a cold refresh must still be diffed, not baselined.
    final before = _onAdded == null ? null : await stored(key);
    final chapters = List<ChapterInfo>.unmodifiable(await source.chapters(url));
    _cache[key] = chapters;
    _changed(key);
    await _kv?.set(
      _kvKey(key),
      jsonEncode([for (final c in chapters) c.toJson()]),
    );
    if (before != null) _report(key, before, chapters);
    return chapters;
  }

  void _report(MangaKey key, List<ChapterInfo> before, List<ChapterInfo> now) {
    final known = {for (final c in before) c.url};
    final added = [
      for (final c in now)
        if (!known.contains(c.url)) c,
    ];
    if (added.isNotEmpty) _onAdded!(key, readingOrder(added));
  }

  /// The stored chapters of [key] (memory cache, else the key-value copy),
  /// or null when this device never fetched them. Never fetches.
  Future<List<ChapterInfo>?> stored(MangaKey key) async =>
      _cache[key] ?? await _restore(key);

  Future<List<ChapterInfo>?> _restore(MangaKey key) async {
    final raw = await _kv?.get(_kvKey(key));
    if (raw == null || _cache.containsKey(key)) return _cache[key];
    // Batched with every other restore of this turn, off the UI isolate
    // when large (the cold-start burst of unread badges).
    final chapters = await _decoder.decode(raw);
    // A fetch may have landed meanwhile; it is newer than the stored copy.
    if (chapters == null || _cache.containsKey(key)) return _cache[key];
    _cache[key] = chapters;
    _changed(key);
    return chapters;
  }

  static String _kvKey(MangaKey key) => 'browse.chapters.${mangaKeyHash(key)}';

  /// Current cached chapters of [key] (null when none), then every update.
  Stream<List<ChapterInfo>?> watch(MangaKey key) {
    late StreamController<List<ChapterInfo>?> out;
    out = StreamController<List<ChapterInfo>?>(
      onListen: () {
        out.add(_cache[key]);
        (_watchers[key] ??= {}).add(out);
        if (_cache[key] == null) unawaited(_restore(key));
      },
      onCancel: () {
        final watchers = _watchers[key]?..remove(out);
        if (watchers != null && watchers.isEmpty) _watchers.remove(key);
      },
    );
    return out.stream;
  }
}
