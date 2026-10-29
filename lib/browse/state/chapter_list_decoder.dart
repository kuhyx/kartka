import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/models.dart';

/// A burst of stored lists at least this long (in total) is decoded in a
/// background isolate; below it, an isolate costs more than the decode.
const int chapterDecodeOffUiChars = 64 * 1024;

/// Decodes stored chapter lists (`ChapterStore` restores) in batches.
///
/// At startup every library row's unread badge restores its manga's list
/// at once: N JSON decodes on the UI isolate in one turn was the cold-start
/// freeze. Every [decode] issued before the current microtasks drain joins
/// one batch, decoded once, off the UI isolate when large (`compute`, which
/// runs inline on web).
class ChapterListDecoder {
  final _pending = <(String, Completer<List<ChapterInfo>?>)>[];

  /// Decode passes run so far (tests check that bursts share one).
  int batches = 0;

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
  for (final text in texts) _decodeOne(text),
];

List<ChapterInfo>? _decodeOne(String text) {
  try {
    return List.unmodifiable([
      for (final c in jsonDecode(text) as List<Object?>)
        ChapterInfo.fromJson(c! as Map<String, Object?>),
    ]);
  } on Object {
    return null; // Corrupt entry: behave as uncached; next load rewrites.
  }
}
