import 'dart:typed_data';

import 'package:kartka/platform/platform.dart';

/// In-memory [BlobStore] that validates keys like the real ones.
class MemoryBlobs implements BlobStore {
  final Map<String, Uint8List> data = {};

  @override
  Future<void> put(String key, Uint8List bytes) async {
    checkBlobKey(key);
    data[key] = bytes;
  }

  @override
  Future<Uint8List?> get(String key) async => data[key];

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<List<String>> list(String prefix) async =>
      data.keys.where((k) => k.startsWith(prefix)).toList()..sort();
}

/// In-memory [KeyValueStore].
class MemoryKv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

/// [FilePicker] that returns preset picks and records the requests.
class FakePicker implements FilePicker {
  List<PickedFile> files = [];
  List<PickedFile> directory = [];
  final List<String> calls = [];

  @override
  Future<List<PickedFile>> pickFiles({
    List<String> extensions = const [],
    bool multiple = false,
  }) async {
    calls.add('files:${extensions.join(',')}:$multiple');
    return files;
  }

  @override
  Future<List<PickedFile>> pickDirectory() async {
    calls.add('directory');
    return directory;
  }
}

/// A picked file holding [bytes].
PickedFile picked(String name, List<int> bytes, {String? relativePath}) =>
    PickedFile(
      name: name,
      relativePath: relativePath,
      read: () async => Uint8List.fromList(bytes),
    );
