import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/coalescing_saver.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';
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

/// [KeyValueStore] as [kvShardCount] JSON shard files in [dir] (Android).
///
/// Every key is held in memory, read once at startup. A save hands only
/// the changed keys to a background isolate, which patches the shards
/// holding them into their files (tmp + rename, so a crash leaves the
/// previous version of each, never half a file): the UI isolate does
/// O(changed keys) per save, never a copy of whole shards. The files are
/// the patch base, so a shard file deleted behind the store's back is not
/// rebuilt from memory (a corrupt one is moved aside, as at startup). Saves
/// are coalesced: changes within one window (250 ms) cost one write, an
/// unchanged value costs none, and the app shell calls [flush] when the app
/// leaves the foreground (`flushOnBackground` in create_platform_io.dart).
///
/// [legacy] is the old single kv.json; its keys are copied into the shards
/// once, and it is then kept as `kv.json.migrated` (kv_shard_files.dart).
class FileKeyValueStore implements KeyValueStore {
  /// Persists to [dir], at most once per [window] while changes keep coming.
  new(
    this.dir, {
    this.legacy,
    Duration window = const Duration(milliseconds: 250),
  }) {
    _saver = CoalescingSaver(_save, window: window);
  }

  /// The shard directory.
  final Directory dir;

  /// The pre-shard kv.json to migrate from, if any.
  final File? legacy;

  late final CoalescingSaver _saver;
  // Key -> new value (null: removed), since the last save.
  final Map<String, String?> _changes = {};
  // One shared read: concurrent first calls must not each load the files
  // and replace one another's maps (a set into the loser would be lost).
  late final Future<List<Map<String, String>>> _shards = _readOff(
    dir.path,
    legacy?.path,
  );

  /// Entries handed to the writer isolate so far (the save-cost tests
  /// bound it: the UI isolate copies them).
  @visibleForTesting
  int sentEntries = 0;

  /// Whether a change has not been written yet.
  bool get pending => _saver.pending;

  /// Writes any pending change to [dir] now.
  Future<void> flush() => _saver.flush();

  Future<void> _save() async {
    // The load must finish first: the shard files are the patch base.
    await _shards;
    // Taken now: a set during the write is saved by the next one.
    final batch = Map.of(_changes);
    _changes.clear();
    sentEntries += batch.length;
    try {
      await _patchOff(dir.path, batch);
    } on Object {
      // Newer changes made during the write win over the failed batch.
      for (final MapEntry(:key, :value) in batch.entries) {
        _changes.putIfAbsent(key, () => value);
      }
      rethrow;
    }
  }

  void _changed(String key, String? value) {
    _changes[key] = value;
    _saver.schedule();
  }

  @override
  Future<String?> get(String key) async => (await _shards)[kvShardOf(key)][key];

  @override
  Future<void> set(String key, String value) async {
    final shard = kvShardOf(key);
    final values = (await _shards)[shard];
    if (values[key] == value) return;
    values[key] = value;
    _changed(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final shard = kvShardOf(key);
    if ((await _shards)[shard].remove(key) != null) _changed(key, null);
  }

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final shard in await _shards)
      for (final e in shard.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

// Top-level, so each isolate closure captures only its arguments.
Future<List<Map<String, String>>> _readOff(String dir, String? legacy) =>
    Isolate.run(() => readKvDir(dir, legacy));

Future<void> _patchOff(String dir, Map<String, String?> changes) =>
    Isolate.run(() => patchKvShards(dir, changes));
