/// The on-disk layout of the Android `KeyValueStore`: [kvShardCount] JSON
/// files in one directory, a key living in shard [kvShardOf], so a save
/// rewrites only the shards it touched (not every key, as one kv.json did).
///
/// Everything here runs inside `Isolate.run` (file_stores.dart) and is
/// plain synchronous I/O, so it is also unit-tested on the main isolate.
library;

import 'dart:convert';
import 'dart:io';

/// Number of shard files. Fixed forever: changing it (or [kvShardOf]) would
/// leave a key in two files, so a stale copy could come back.
const kvShardCount = 64;

/// Written once the legacy kv.json has been copied into the shards.
const kvMigratedMarker = '.migrated';

/// The shard of [key]: 32-bit FNV-1a over its UTF-16 code units. Never
/// `String.hashCode`, which is not guaranteed stable across SDK versions.
int kvShardOf(String key) {
  var h = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xffffffff;
  }
  return h % kvShardCount;
}

/// File name of shard [shard] inside the store directory.
String kvShardFileName(int shard) =>
    'shard-${shard.toString().padLeft(2, '0')}.json';

/// [values] split into their shards (every shard present, maybe empty).
List<Map<String, String>> groupKvShards(Map<String, String> values) {
  final shards = List.generate(kvShardCount, (_) => <String, String>{});
  for (final MapEntry(:key, :value) in values.entries) {
    shards[kvShardOf(key)][key] = value;
  }
  return shards;
}

/// Every shard's entries merged into one map (tests and migration checks).
Map<String, String> flattenShards(List<Map<String, String>> shards) => {
  for (final s in shards) ...s,
};

/// Loads every shard of [dir], first migrating [legacy] (the old single
/// kv.json) when the directory has no [kvMigratedMarker] yet.
///
/// Migration order makes it resumable: shards (tmp + flush + rename), then
/// the flushed marker, then kv.json is renamed to `kv.json.migrated`,
/// never deleted. With no marker it is redone, from kv.json or else from
/// `kv.json.migrated` (a crash can persist the rename yet lose the marker
/// and shard renames); the store serves nothing until this returns, so at
/// worst that drops seconds of writes, never the library. A corrupt
/// kv.json is renamed to `kv.json.corrupt` and the store starts empty; the
/// old code would have overwritten it on the next save.
List<Map<String, String>> readKvDir(String dir, String? legacy) {
  final marker = File('$dir/$kvMigratedMarker');
  final source = legacy == null || marker.existsSync()
      ? null
      : [File(legacy), File('$legacy.migrated')].where((f) => f.existsSync());
  if (source != null && source.isNotEmpty) {
    final old = source.first;
    final values = _decodeObject(old.readAsStringSync());
    if (values != null) writeKvShards(dir, {..._indexed(values)});
    Directory(dir).createSync(recursive: true);
    marker.writeAsStringSync(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
    if (old.path == legacy) {
      old.renameSync('$legacy.${values == null ? 'corrupt' : 'migrated'}');
    }
  }
  return [for (var i = 0; i < kvShardCount; i++) _readShard(dir, i)];
}

Map<int, Map<String, String>> _indexed(Map<String, String> values) =>
    groupKvShards(values).asMap();

Map<String, String> _readShard(String dir, int shard) {
  final file = File('$dir/${kvShardFileName(shard)}');
  if (!file.existsSync()) return {};
  final values = _decodeObject(file.readAsStringSync());
  if (values != null) return values;
  // Kept for recovery; the next save of this shard writes a fresh file.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  file.renameSync('${file.path}.corrupt-$stamp');
  return {};
}

/// The string entries of a JSON object, or null when [text] is not one.
Map<String, String>? _decodeObject(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  return {
    for (final MapEntry(:key, :value) in decoded.entries)
      if (value is String) key: value,
  };
}

/// Writes [shards] (index → entries) into [dir] in two phases: every
/// `.tmp` is written and flushed, then all are renamed. A crash leaves
/// each shard whole (old or new); only a crash between the renames can
/// mix shards of two consecutive saves.
void writeKvShards(String dir, Map<int, Map<String, String>> shards) {
  Directory(dir).createSync(recursive: true);
  final written = <File, String>{};
  for (final MapEntry(key: shard, value: values) in shards.entries) {
    final path = '$dir/${kvShardFileName(shard)}';
    final tmp = File('$path.tmp')
      ..writeAsStringSync(jsonEncode(values), flush: true);
    written[tmp] = path;
  }
  written.forEach((tmp, path) => tmp.renameSync(path));
}
