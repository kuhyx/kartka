import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/startup_marks.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';

/// The library waits on the whole kv load (~20 MB of shards on the phone,
/// ~0.9 s on one core: perf.slow a133bbb8), so the shards are parsed in
/// [kvReadGroups] isolates at once once no migration is pending.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_kvp'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the read groups cover every shard once, in order', () {
    final all = [
      for (final (from, to) in kvReadRanges())
        for (var i = from; i < to; i++) i,
    ];
    expect(all, [for (var i = 0; i < kvShardCount; i++) i]);
    expect(kvReadRanges(), hasLength(kvReadGroups));
  });

  test('ranges read the same rows as the whole directory', () {
    final values = {for (var i = 0; i < 300; i++) 'k$i': 'v$i'};
    writeKvShards(dir.path, groupKvShards(values).asMap());
    final parts = [
      for (final (from, to) in kvReadRanges())
        ...readKvShards(dir.path, from, to),
    ];
    expect(parts, readKvDir(dir.path, null));
    expect(flattenShards(parts), values);
  });

  test('a pending migration is seen until the marker is written', () {
    final legacy = File('${dir.path}/kv.json')..writeAsStringSync('{"a":"1"}');
    final kv = '${dir.path}/kv';
    expect(kvMigrationPending(kv, legacy.path), isTrue);
    expect(kvMigrationPending(kv, null), isFalse);
    readKvDir(kv, legacy.path);
    expect(kvMigrationPending(kv, legacy.path), isFalse);
  });

  test('a store over migrated shards reads every key', () async {
    final kv = Directory('${dir.path}/kv');
    final values = {for (var i = 0; i < 200; i++) 'library/$i': '$i'};
    writeKvShards(kv.path, groupKvShards(values).asMap());
    File('${kv.path}/$kvMigratedMarker').writeAsStringSync('x');
    final store = FileKeyValueStore(kv, legacy: File('${dir.path}/kv.json'));
    expect(await store.entries(prefix: 'library/'), values);
  });

  test('warm starts the one read at once and marks the launch', () async {
    final kv = Directory('${dir.path}/kv');
    writeKvShards(kv.path, groupKvShards({'a': '1'}).asMap());
    final marks = StartupMarks();
    final store = FileKeyValueStore(kv, marks: marks)..warm();
    // Before any caller: createPlatform warms it, so the 20 MB read runs
    // beside app start-up instead of after it (library.load a133bbb8).
    expect(marks.marks, contains('kv.read'));
    expect(marks.marks, isNot(contains('kv.done')));
    expect(await store.get('a'), '1');
    expect(marks.marks, contains('kv.done'));
  });
}
