import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';

void main() {
  late Directory dir;
  late Directory kvDir;
  late File legacy;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('kartka_kv');
    kvDir = Directory('${dir.path}/kv');
    legacy = File('${dir.path}/kv.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FileKeyValueStore open() => FileKeyValueStore(kvDir, legacy: legacy);
  List<String> shardFiles() => kvDir.existsSync()
      ? (kvDir
            .listSync()
            .map((e) => e.uri.pathSegments.last)
            .where((n) => n.startsWith('shard-'))
            .toList()
          ..sort())
      : [];

  test('the shard of a key is fixed forever (stable FNV-1a, 64 shards)', () {
    // Pinned: a changed mapping would leave a key in two files.
    expect(kvShardCount, 64);
    expect(kvShardOf(''), 2166136261 % 64);
    expect(kvShardOf('library/abc'), 3);
    expect(kvShardOf('progress/0f3a'), 25);
    expect(kvShardOf('sync.b.read/x'), 47);
    expect(kvShardFileName(3), 'shard-03.json');
  });

  test('an unchanged set schedules no write', () async {
    final kv = open();
    await kv.set('a', '1');
    await kv.flush();
    expect(kv.pending, isFalse);
    await kv.set('a', '1');
    expect(kv.pending, isFalse, reason: 'same value, nothing to save');
    await kv.remove('missing');
    expect(kv.pending, isFalse);
    await kv.set('a', '2');
    expect(kv.pending, isTrue);
  });

  test('a set rewrites only the shard holding its key', () async {
    final kv = open();
    for (var i = 0; i < 300; i++) {
      await kv.set('library/$i', 'v$i');
    }
    await kv.flush();
    expect(shardFiles(), hasLength(64), reason: '300 keys fill every shard');
    for (final f in kvDir.listSync()) {
      f.deleteSync();
    }
    await kv.set('library/7', 'changed');
    await kv.flush();
    expect(shardFiles(), [kvShardFileName(kvShardOf('library/7'))]);
    final again = open();
    expect(await again.get('library/7'), 'changed');
  });

  test('migration from kv.json keeps every key and the old file', () async {
    final old = {
      for (var i = 0; i < 2000; i++) 'library/$i': '{"t":"ż$i"}',
      'sync.lastSync': '2026-10-29T00:00:00.000Z',
      '': 'empty key',
    };
    final text = jsonEncode(old);
    legacy.writeAsStringSync(text);
    final kv = open();
    expect(await kv.entries(), old);
    expect(legacy.existsSync(), isFalse);
    expect(File('${legacy.path}.migrated').readAsStringSync(), text);
    expect(File('${kvDir.path}/$kvMigratedMarker').existsSync(), isTrue);
    expect(await open().entries(), old, reason: 'reads the shards now');
  });

  test('an interrupted migration (no marker) is redone from kv.json', () {
    legacy.writeAsStringSync(jsonEncode({'a': '1', 'b': '2'}));
    kvDir.createSync();
    File('${kvDir.path}/${kvShardFileName(kvShardOf('a'))}')
        .writeAsStringSync('{"a":"half-written"}');
    final values = readKvDir(kvDir.path, legacy.path);
    expect(flattenShards(values), {'a': '1', 'b': '2'});
  });

  test('a crash that kept only the rename re-migrates from the backup', () {
    // The rename reached disk, the marker and shard renames did not.
    File('${legacy.path}.migrated').writeAsStringSync('{"a":"1","b":"2"}');
    final values = readKvDir(kvDir.path, legacy.path);
    expect(flattenShards(values), {'a': '1', 'b': '2'});
    expect(File('${kvDir.path}/$kvMigratedMarker').existsSync(), isTrue);
    expect(File('${legacy.path}.migrated').existsSync(), isTrue);
  });

  test('marker present: kv.json is ignored, the shards win', () {
    legacy.writeAsStringSync(jsonEncode({'a': 'old'}));
    writeKvShards(kvDir.path, {
      kvShardOf('a'): {'a': 'new'},
    });
    File('${kvDir.path}/$kvMigratedMarker').writeAsStringSync('done');
    expect(flattenShards(readKvDir(kvDir.path, legacy.path)), {'a': 'new'});
    expect(legacy.readAsStringSync(), '{"a":"old"}', reason: 'untouched');
  });

  test('a corrupt kv.json is kept aside, never overwritten', () async {
    legacy.writeAsStringSync('{nope');
    final kv = open();
    expect(await kv.entries(), isEmpty);
    await kv.set('k', 'v');
    await kv.flush();
    expect(File('${legacy.path}.corrupt').readAsStringSync(), '{nope');
    expect(await open().get('k'), 'v');
  });

  test('non-string values in kv.json are dropped, strings kept', () {
    legacy.writeAsStringSync('{"a":"1","n":2}');
    expect(flattenShards(readKvDir(kvDir.path, legacy.path)), {'a': '1'});
  });

  test('a corrupt shard is moved aside and reads as empty', () async {
    final name = kvShardFileName(kvShardOf('x'));
    writeKvShards(kvDir.path, {
      kvShardOf('x'): {'x': '1'},
    });
    File('${kvDir.path}/$name').writeAsStringSync('{bad');
    final kv = open();
    expect(await kv.get('x'), isNull);
    expect(
      kvDir.listSync().map((e) => e.path).where((p) => p.contains('.corrupt')),
      hasLength(1),
    );
  });

  test('a failed save keeps its change and the next flush writes it', () async {
    final kv = open();
    await kv.set('a', '1');
    await kv.flush();
    kvDir.deleteSync(recursive: true);
    File(kvDir.path).writeAsStringSync('in the way');
    await kv.set('a', '2');
    await expectLater(kv.flush(), throwsA(isA<Object>()));
    File(kvDir.path).deleteSync();
    await kv.flush();
    expect(await open().get('a'), '2');
  });

  test('no store: an empty directory, no legacy file', () async {
    final kv = FileKeyValueStore(kvDir);
    expect(await kv.entries(prefix: 'x'), isEmpty);
    expect(readKvDir(kvDir.path, null), hasLength(kvShardCount));
  });
}
