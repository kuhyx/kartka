import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';

// Top-level: it is sent to the isolate.
int? _length(String text) => text == 'bad' ? null : text.length;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_kv_dec'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileKeyValueStore open() => FileKeyValueStore(Directory('${dir.path}/kv'));

  Future<void> seed() async {
    final kv = open();
    for (var i = 0; i < 300; i++) {
      await kv.set('k$i', 'v' * (i + 1));
    }
    await kv.set('bad', 'bad');
    await kv.flush();
  }

  test(
    'values are read and decoded in the isolate, none copied to it',
    () async {
      await seed();
      final kv = open();
      final keys = ['k0', 'k299', 'missing', 'bad', 'k7'];

      final out = await kv.decodeAll<int>(keys, _length);

      expect(out, [1, 300, null, null, 8]);
      // Before: every value was read on the UI isolate and sent as a string.
      expect(kv.copiedChars, 0);
    },
  );

  test(
    'a key written this launch is served from memory, even unsaved',
    () async {
      await seed();
      final kv = open();
      await kv.set('k1', 'new value');
      await kv.remove('k2');
      await kv.set('fresh', 'abc');

      // The write is still pending: the file holds the old value.
      expect(kv.pending, isTrue);
      expect(await kv.decodeAll<int>(['k1', 'k2', 'fresh', 'k3'], _length), [
        9,
        null,
        3,
        4,
      ]);
      expect(kv.copiedChars, 'new value'.length + 'abc'.length);
      await kv.flush();
      expect(await kv.decodeAll<int>(['k1'], _length), [9]);
    },
  );

  test(
    'a shard corrupted behind the store reads as absent, untouched',
    () async {
      await seed();
      final kv = open();
      await kv.get('k5'); // loaded: the shards are read once, at startup
      final file = File('${dir.path}/kv/${kvShardFileName(kvShardOf('k5'))}')
        ..writeAsStringSync('{broken');
      expect(await kv.decodeAll<int>(['k5'], _length), [null]);
      expect(file.readAsStringSync(), '{broken', reason: 'not moved aside');
    },
  );

  test('no keys, no shard files: nothing to read', () async {
    final kv = open();
    expect(await kv.decodeAll<int>([], _length), isEmpty);
    expect(await kv.decodeAll<int>(['a'], _length), [null]);
  });
}
