/// Small persistent string settings and state (DOCS-contracts §7).
///
/// Android: a JSON file in the app's support directory. Web: IndexedDB
/// (survives far longer than localStorage and is not capped at ~5 MB).
abstract interface class KeyValueStore {
  /// The value under [key], or `null`.
  Future<String?> get(String key);

  /// Stores [value] under [key].
  Future<void> set(String key, String value);

  /// Removes [key]; a missing key is not an error.
  Future<void> remove(String key);

  /// Every entry whose key starts with [prefix].
  Future<Map<String, String>> entries({String prefix = ''});
}

/// A [KeyValueStore] that can decode stored values in a background isolate
/// without the UI isolate reading them first.
///
/// Sending a string to an isolate copies it, so decoding N big values via
/// `get` + `compute` cost the UI isolate a read and a copy of every one of
/// them (the cold-start chapter lists). Stores that can hand the work the
/// *keys* implement this; callers fall back to `get` for the rest.
abstract interface class OffUiDecodingStore implements KeyValueStore {
  /// `decode(value)` for each of [keys], in order, `null` where the key is
  /// absent or [decode] returns `null`. [decode] must be a top-level or
  /// static function (it is sent to an isolate); its results must be
  /// sendable.
  Future<List<R?>> decodeAll<R extends Object>(
    List<String> keys,
    R? Function(String text) decode,
  );
}
