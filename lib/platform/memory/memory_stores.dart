import 'dart:typed_data';

import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/key_value_store.dart';

/// In-memory [BlobStore] for tests; copies bytes in and out.
class MemoryBlobStore implements BlobStore {
  final _blobs = <String, Uint8List>{};

  @override
  Future<void> put(String key, Uint8List bytes) async {
    checkBlobKey(key);
    _blobs[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> get(String key) async {
    checkBlobKey(key);
    final bytes = _blobs[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String key) async {
    checkBlobKey(key);
    _blobs.remove(key);
  }

  @override
  Future<List<String>> list(String prefix) async =>
      _blobs.keys.where((k) => k.startsWith(prefix)).toList()..sort();
}

/// In-memory [KeyValueStore] for tests, optionally seeded.
class MemoryKeyValueStore implements KeyValueStore {
  /// Creates a store holding a copy of [seed].
  new([Map<String, String> seed = const {}]) : _values = Map.of(seed);

  final Map<String, String> _values;

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in _values.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}
