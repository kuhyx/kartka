import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/key_value_store.dart';

/// A burst of stored lists at least this long (in total) is decoded in a
/// background isolate; below it, an isolate costs more than the decode.
const int chapterDecodeOffUiChars = 64 * 1024;

/// Restores stored chapter lists (`ChapterStore` restores) in batches.
///
/// At startup every library row's unread badge restores its manga's list
/// at once: N JSON decodes on the UI isolate in one turn was the cold-start
/// freeze. Every restore issued before the current microtasks drain joins
/// one batch.
///
/// Over a store that decodes by key ([OffUiDecodingStore], Android) the
/// batch hands the *keys* to a background isolate, which reads and decodes
/// the lists itself: the UI isolate neither reads nor copies any list text.
/// Over any other store each text is read, then decoded in one pass, off
/// the UI isolate when large (`compute`, which runs inline on web).
class ChapterListDecoder {
  /// Restores from [_kv] (the lists' store), if any.
  new([this._kv]);

  final KeyValueStore? _kv;
  final _pending = <(String, Completer<List<ChapterInfo>?>)>[];

  /// Decode passes run so far (tests check that bursts share one).
  int batches = 0;

  /// The list stored under [key], or null when absent or corrupt.
  Future<List<ChapterInfo>?> restore(String key) async {
    final kv = _kv;
    if (kv is! OffUiDecodingStore) {
      final raw = await kv?.get(key);
      return raw == null ? null : await decode(raw);
    }
    final done = Completer<List<ChapterInfo>?>();
    if (_pending.isEmpty) scheduleMicrotask(() => unawaited(_runKeys(kv)));
    _pending.add((key, done));
    return await done.future;
  }

  Future<void> _runKeys(OffUiDecodingStore kv) async {
    final batch = [..._pending];
    _pending.clear();
    batches++;
    try {
      final lists = await kv.decodeAll([
        for (final (key, _) in batch) key,
      ], decodeChapterList);
      for (var i = 0; i < batch.length; i++) {
        batch[i].$2.complete(lists[i]);
      }
    } on Object {
      // An unreadable store behaves as an uncached list: it is fetched.
      for (final (_, done) in batch) {
        done.complete(null);
      }
    }
  }

  /// The chapters stored as [text], or null when it is corrupt.
  Future<List<ChapterInfo>?> decode(String text) {
    final done = Completer<List<ChapterInfo>?>();
    if (_pending.isEmpty) scheduleMicrotask(() => unawaited(_run()));
    _pending.add((text, done));
    return done.future;
  }

  Future<void> _run() async {
    final batch = [..._pending];
    _pending.clear();
    batches++;
    final texts = [for (final (text, _) in batch) text];
    final total = texts.fold(0, (n, t) => n + t.length);
    final lists = total < chapterDecodeOffUiChars
        ? decodeChapterLists(texts)
        : await compute(decodeChapterLists, texts);
    for (var i = 0; i < batch.length; i++) {
      batch[i].$2.complete(lists[i]);
    }
  }
}

/// Each of [texts] as an unmodifiable chapter list, or null when corrupt.
List<List<ChapterInfo>?> decodeChapterLists(List<String> texts) => [
  for (final text in texts) decodeChapterList(text),
];

/// [text] as an unmodifiable chapter list, or null when it is corrupt.
List<ChapterInfo>? decodeChapterList(String text) {
  try {
    return List.unmodifiable([
      for (final c in jsonDecode(text) as List<Object?>)
        ChapterInfo.fromJson(c! as Map<String, Object?>),
    ]);
  } on Object {
    return null; // Corrupt entry: behave as uncached; next load rewrites.
  }
}
