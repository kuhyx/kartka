import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/storage_routes.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.start());
  tearDown(() => h.close());

  test('/files stores blobs as files', () async {
    expect(jsonDecode(text(await h.call('GET', '/files'))), isEmpty);
    expect((await h.call('PUT', '/files/pages/a/2', body: [2])).status, 204);
    await h.call('PUT', '/files/pages/a/1', body: [1, 1]);
    await h.call('PUT', '/files/covers/x', body: [9]);
    expect(File('${h.dir.path}/files/pages/a/1').readAsBytesSync(), [1, 1]);
    expect((await h.call('GET', '/files/pages/a/1')).body, [1, 1]);
    expect((await h.call('GET', '/files/pages/zz')).status, 404);
    final list = await h.call('GET', '/files?prefix=pages/');
    expect(jsonDecode(text(list)), ['pages/a/1', 'pages/a/2']);
    expect((await h.call('DELETE', '/files/pages/a/1')).status, 204);
    expect((await h.call('DELETE', '/files/pages/a/1')).status, 204);
    expect(jsonDecode(text(await h.call('GET', '/files'))), [
      'covers/x',
      'pages/a/2',
    ]);
    expect((await h.call('POST', '/files/a', body: [1])).status, 405);
  });

  test('/files rejects keys that escape the root', () async {
    expect(
      (await h.call('PUT', '/files/a%2F..%2F..%2Fx', body: [1])).status,
      400,
    );
    // HttpServer collapses decoded dot segments first: this lands inside.
    await h.call('PUT', '/files/a/%2E%2E/b', body: [1]);
    expect(File('${h.dir.path}/files/b').existsSync(), isTrue);
    expect((await h.call('GET', '/files/a%20b')).status, 400);
    expect(isValidBlobKey('a/b.c_d-1'), isTrue);
    expect(isValidBlobKey('a//b'), isFalse);
  });

  test('/secrets keeps a 0600 file in a 0700 directory', () async {
    expect((await h.call('GET', '/secrets/anilist.token')).status, 404);
    final put = await h.call(
      'PUT',
      '/secrets/anilist.token',
      body: utf8.encode('tok ż'),
    );
    expect(put.status, 204);
    await h.call('PUT', '/secrets/mal.token', body: utf8.encode('m'));
    expect(text(await h.call('GET', '/secrets/anilist.token')), 'tok ż');
    final some = await h.call('GET', '/secrets?prefix=anilist.');
    expect(jsonDecode(text(some)), {'anilist.token': 'tok ż'});
    final file = File('${h.dir.path}/config/kartka/secrets.json');
    expect(file.statSync().mode & 0x1ff, 0x180); // 0600
    expect(file.parent.statSync().mode & 0x1ff, 0x1c0); // 0700
    expect((await h.call('DELETE', '/secrets/anilist.token')).status, 204);
    expect((await h.call('DELETE', '/secrets/anilist.token')).status, 204);
    expect(jsonDecode(text(await h.call('GET', '/secrets'))), {
      'mal.token': 'm',
    });
    expect((await h.call('PUT', '/secrets/a%2Fb', body: [1])).status, 400);
    expect((await h.call('POST', '/secrets/a', body: [1])).status, 405);
  });
}
