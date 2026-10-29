import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_kv_cost'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileKeyValueStore open() => FileKeyValueStore(Directory('${dir.path}/kv'));

  test('a save copies only the changed keys, not their shards', () async {
    final kv = open();
    // ~100 keys per shard, as a 775-manga library has.
    for (var i = 0; i < 6400; i++) {
      await kv.set('browse.chapters.$i', 'v$i');
    }
    await kv.flush();
    kv.sentEntries = 0;
    await kv.set('progress/1', 'p');
    await kv.remove('browse.chapters.3');
    await kv.flush();
    expect(kv.sentEntries, 2, reason: 'one set + one remove');

    final again = open();
    expect(await again.get('progress/1'), 'p');
    expect(await again.get('browse.chapters.3'), isNull);
    expect(await again.get('browse.chapters.4'), 'v4', reason: 'kept');
    expect(await again.entries(prefix: 'browse.'), hasLength(6399));
  });

  test('a change during a save is written by the next one', () async {
    final kv = open();
    await kv.set('a', '1');
    final saving = kv.flush();
    await kv.set('a', '2');
    await kv.set('b', '1');
    await saving;
    await kv.flush();
    expect(await open().entries(), {'a': '2', 'b': '1'});
  });

  test('patching a corrupt shard moves it aside and starts it empty', () {
    final path = dir.path;
    writeKvShards(path, {
      kvShardOf('x'): {'x': '1'},
    });
    File('$path/${kvShardFileName(kvShardOf('x'))}').writeAsStringSync('{');
    patchKvShards(path, {'x': '2', 'gone': null});
    expect(flattenShards(readKvDir(path, null)), {'x': '2'});
    expect(
      Directory(path).listSync().where((e) => e.path.contains('.corrupt')),
      hasLength(1),
    );
  });
}
