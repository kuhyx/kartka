import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_addition_sink.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/platform/key_value_store.dart';

/// One chapter that newly appeared in a library manga.
@immutable
class UpdateEvent {
  /// [chapter] of [key], found at [foundAt] (UTC).
  const new({required this.key, required this.chapter, required this.foundAt});

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => UpdateEvent(
    key: readString(json, 'key'),
    chapter: ChapterInfo.fromJson(readObject(json['chapter'])),
    foundAt: readDate(json, 'foundAt'),
  );

  /// The manga.
  final MangaKey key;

  /// The new chapter (enough to render and open it without a fetch).
  final ChapterInfo chapter;

  /// When kartka first stored it.
  final DateTime foundAt;

  /// JSON with a UTC ISO-8601 instant.
  Map<String, Object?> toJson() => {
    'key': key,
    'chapter': chapter.toJson(),
    'foundAt': foundAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is UpdateEvent &&
      other.key == key &&
      other.chapter == chapter &&
      other.foundAt.isAtSameMomentAs(foundAt);

  @override
  int get hashCode => Object.hash(key, chapter, foundAt.microsecondsSinceEpoch);
}

/// The local updates feed: new chapters of library manga, newest first,
/// one JSON value in the key-value store, at most [cap] events and none
/// older than [maxAge]. Fed by browse's chapter store through
/// [ChapterAdditionSink], so every path that stores a grown list counts.
///
/// Writes are serialised against one in-memory list, so parallel checks
/// never lose an event; a chapter already in the feed is not added again.
class UpdateFeed extends ChangeNotifier implements ChapterAdditionSink {
  /// Creates the feed over [_kv]; [inLibrary] filters out manga that are
  /// only being browsed.
  new(
    this._kv, {
    required this.inLibrary,
    this.clock = utcNow,
    this.cap = 500,
    this.maxAge = const Duration(days: 60),
  });

  /// Where the feed is stored.
  static const storageKey = 'updates.feed';

  final KeyValueStore _kv;

  /// Whether a manga is in the library (only those are recorded).
  final Future<bool> Function(MangaKey key) inLibrary;

  /// Clock for `foundAt` and pruning.
  final DateTime Function() clock;

  /// Most events kept.
  final int cap;

  /// Oldest event kept.
  final Duration maxAge;

  List<UpdateEvent> _events = const [];
  Future<void>? _loading;
  Future<void> _tail = Future.value();

  /// Events, newest first (empty until [load] finished).
  List<UpdateEvent> get events => _events;

  /// Whether the stored feed was read.
  bool loaded = false;

  /// Reads the stored feed once; later calls share the first read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await _kv.get(storageKey);
    try {
      _events = _prune([
        for (final e in jsonDecode(raw ?? '[]') as List<Object?>)
          UpdateEvent.fromJson(e! as Map<String, Object?>),
      ]);
    } on Object {
      _events = const []; // Corrupt: start over; the next record rewrites.
    }
    loaded = true;
    notifyListeners();
  }

  @override
  Future<void> record(MangaKey key, List<ChapterInfo> added) {
    final run = _tail.then((_) => _record(key, added));
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _record(MangaKey key, List<ChapterInfo> added) async {
    if (added.isEmpty) return;
    await load();
    if (!await inLibrary(key)) return;
    final at = clock();
    final known = {
      for (final e in _events)
        if (e.key == key) e.chapter.url,
    };
    final fresh = [
      for (final c in added.reversed)
        if (known.add(c.url)) UpdateEvent(key: key, chapter: c, foundAt: at),
    ];
    if (fresh.isEmpty) return;
    _events = _prune([...fresh, ..._events]);
    notifyListeners();
    await _kv.set(
      storageKey,
      jsonEncode([for (final e in _events) e.toJson()]),
    );
  }

  List<UpdateEvent> _prune(List<UpdateEvent> events) {
    final oldest = clock().subtract(maxAge);
    return List.unmodifiable(
      events.where((e) => !e.foundAt.isBefore(oldest)).take(cap),
    );
  }
}
