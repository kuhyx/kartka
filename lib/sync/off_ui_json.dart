/// JSON decoding that keeps big payloads (full RTDB pulls, the persisted
/// shadow) off the UI isolate, so they cannot drop frames.
///
/// Below [offUiJsonChars] the work is cheaper than spawning an isolate, and
/// stays inline (which also keeps widget tests, whose fake clock cannot
/// wait for an isolate, on the inline path). `compute` runs inline on web.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Payloads at least this long are decoded in a background isolate.
const int offUiJsonChars = 64 * 1024;

/// Background-isolate decodes started so far (tests check which loads leave
/// the UI isolate).
@visibleForTesting
int offUiRuns = 0;

/// `jsonDecode(text)`, in a background isolate when [text] is large.
Future<Object?> decodeJsonOffUi(String text) async {
  if (text.length < offUiJsonChars) return jsonDecode(text);
  offUiRuns++;
  return await compute(_decode, text);
}

/// Each of [texts] decoded (null when not valid JSON), in one background
/// isolate when they are large together.
Future<List<Object?>> decodeEachOffUi(List<String> texts) async {
  final total = texts.fold(0, (n, t) => n + t.length);
  if (total < offUiJsonChars) return _decodeEach(texts);
  offUiRuns++;
  return await compute(_decodeEach, texts);
}

Object? _decode(String text) => jsonDecode(text);

List<Object?> _decodeEach(List<String> texts) => [
  for (final t in texts) _tryDecode(t),
];

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}
