import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/coalescing_saver.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:path/path.dart' as p;

/// [BlobStore] as plain files under [root] (Android).
class FileBlobStore implements BlobStore {
  /// Stores blobs under [root], created on first write.
  new(this.root);

  /// Directory holding the blobs.
  final Directory root;

  File _file(String key) {
    checkBlobKey(key);
    return File(p.joinAll([root.path, ...key.split('/')]));
  }

  @override
  Future<void> put(String key, Uint8List bytes) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    // Write-then-rename so a crash never leaves a truncated page behind.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> get(String key) async {
    final file = _file(key);
    return file.existsSync() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<List<String>> list(String prefix) async {
    if (!root.existsSync()) return [];
    final keys = <String>[
      await for (final e in root.list(recursive: true))
        if (e is File && !e.path.endsWith('.tmp'))
          p.split(p.relative(e.path, from: root.path)).join('/'),
    ];
    return keys.where((k) => k.startsWith(prefix)).toList()..sort();
  }
}

/// [KeyValueStore] as one JSON object in [file] (Android).
///
/// A save rewrites the whole file (write-then-rename, so a crash leaves the
/// previous version, never half a file). The file reaches several MB after
/// a backup import, so saves are coalesced: changes within one window
/// (250 ms) cost one write, and the app shell calls [flush] when the app
/// leaves the foreground (`flushOnBackground` in create_platform_io.dart).
class FileKeyValueStore implements KeyValueStore {
  /// Persists to [file], at most once per [window] while changes keep coming.
  new(this.file, {Duration window = const Duration(milliseconds: 250)}) {
    _saver = CoalescingSaver(_save, window: window);
  }

  /// The JSON file.
  final File file;

  late final CoalescingSaver _saver;
  Map<String, String>? _cache;

  /// Writes any pending change to [file] now.
  Future<void> flush() => _saver.flush();

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    var values = <String, String>{};
    if (file.existsSync()) {
      try {
        values = (jsonDecode(await file.readAsString()) as Map<String, Object?>)
            .cast<String, String>();
      } on FormatException {
        // A corrupt file is treated as empty rather than bricking startup.
      }
    }
    return _cache = values;
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    // Encoded at write time, so it holds every change made so far.
    await tmp.writeAsString(jsonEncode(_cache), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<String?> get(String key) async => (await _load())[key];

  @override
  Future<void> set(String key, String value) async {
    final values = await _load();
    values[key] = value;
    _saver.schedule();
  }

  @override
  Future<void> remove(String key) async {
    final values = await _load();
    if (values.remove(key) != null) _saver.schedule();
  }

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in (await _load()).entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}
