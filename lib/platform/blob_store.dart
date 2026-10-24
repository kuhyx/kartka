import 'dart:typed_data';

/// Binary storage for downloaded pages and covers (DOCS-contracts §7).
///
/// Android keeps files under the app's documents directory; the web build
/// stores them as files through the desktop wrapper's `/files/` routes.
/// Keys are `/`-separated paths of `[A-Za-z0-9._-]` segments, no `..`
/// (see [isValidBlobKey]); e.g. `pages/<mangaKeyHash>/<chapterHash>/003`.
abstract interface class BlobStore {
  /// Stores [bytes] under [key], replacing any previous value.
  Future<void> put(String key, Uint8List bytes);

  /// The bytes under [key], or `null` when absent.
  Future<Uint8List?> get(String key);

  /// Removes [key]; a missing key is not an error.
  Future<void> delete(String key);

  /// Every key starting with [prefix], sorted.
  Future<List<String>> list(String prefix);
}

final _segment = RegExp(r'^[A-Za-z0-9._-]+$');

/// Whether [key] is a legal [BlobStore] key.
bool isValidBlobKey(String key) {
  if (key.isEmpty) return false;
  return key
      .split('/')
      .every((s) => s != '.' && s != '..' && _segment.hasMatch(s));
}

/// Throws [ArgumentError] unless [key] is a legal [BlobStore] key.
void checkBlobKey(String key) {
  if (!isValidBlobKey(key)) {
    throw ArgumentError.value(key, 'key', 'not a valid blob key');
  }
}
