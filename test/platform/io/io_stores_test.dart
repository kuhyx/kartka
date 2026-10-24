import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/io/directory_files.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/secure_key_value_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_io'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('FileBlobStore keeps blobs as files under its root', () async {
    final store = FileBlobStore(Directory('${dir.path}/blobs'));
    expect(await store.list(''), isEmpty);
    await store.put('pages/a/2', Uint8List.fromList([2]));
    await store.put('pages/a/1', Uint8List.fromList([1]));
    await store.put('covers/x', Uint8List.fromList([9]));
    expect(File('${dir.path}/blobs/pages/a/1').readAsBytesSync(), [1]);
    expect(await store.get('pages/a/1'), [1]);
    expect(await store.get('pages/zzz'), isNull);
    expect(await store.list('pages/'), ['pages/a/1', 'pages/a/2']);
    expect(await store.list('pages/a/1'), ['pages/a/1']);
    await store.delete('pages/a/1');
    await store.delete('pages/a/1');
    expect(await store.list(''), ['covers/x', 'pages/a/2']);
    expect(() => store.get('../etc'), throwsArgumentError);
  });

  test('FileKeyValueStore persists across instances, atomically', () async {
    final file = File('${dir.path}/sub/kv.json');
    final kv = FileKeyValueStore(file);
    expect(await kv.get('a'), isNull);
    await kv.set('a.x', '1');
    await kv.set('a.y', 'ż');
    await kv.set('b', '3');
    await kv.remove('b');
    await kv.remove('missing');
    final again = FileKeyValueStore(file);
    expect(await again.entries(prefix: 'a.'), {'a.x': '1', 'a.y': 'ż'});
    expect(await again.get('b'), isNull);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('FileKeyValueStore treats a corrupt file as empty', () async {
    final file = File('${dir.path}/kv.json')..writeAsStringSync('{nope');
    final kv = FileKeyValueStore(file);
    expect(await kv.entries(), isEmpty);
    await kv.set('k', 'v');
    expect(await FileKeyValueStore(file).get('k'), 'v');
  });

  test('SecureKeyValueStore maps onto flutter_secure_storage', () async {
    FlutterSecureStorage.setMockInitialValues({'kartka.anilist': 't'});
    final kv = SecureKeyValueStore(const FlutterSecureStorage());
    expect(await kv.get('anilist'), 't');
    await kv.set('mal', 'm');
    await kv.remove('anilist');
    expect(await kv.entries(), {'mal': 'm'});
    expect(await kv.entries(prefix: 'x'), isEmpty);
  });

  test('listDirectoryFiles walks a folder with relative paths', () async {
    File('${dir.path}/S/ch1.cbz')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    File('${dir.path}/S/v2/ch2.cbz')
      ..createSync(recursive: true)
      ..writeAsBytesSync([2]);
    final files = await listDirectoryFiles('${dir.path}/S');
    expect(files.map((f) => f.relativePath), ['ch1.cbz', 'v2/ch2.cbz']);
    expect(files.map((f) => f.name), ['ch1.cbz', 'ch2.cbz']);
    expect(await files.last.readBytes(), [2]);
    expect(await listDirectoryFiles(null), isEmpty);
  });
}
