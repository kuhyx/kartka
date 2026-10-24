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
