import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

void main() {
  group('MemoryBlobStore', () {
    test('put/get/list/delete', () async {
      final store = MemoryBlobStore();
      await store.put('pages/a/2', Uint8List.fromList([2]));
      await store.put('pages/a/1', Uint8List.fromList([1]));
      await store.put('covers/x', Uint8List.fromList([9]));
      expect(await store.get('pages/a/1'), [1]);
      expect(await store.get('nope'), isNull);
      expect(await store.list('pages/'), ['pages/a/1', 'pages/a/2']);
      await store.delete('pages/a/1');
      await store.delete('pages/a/1');
      expect(await store.list(''), ['covers/x', 'pages/a/2']);
    });
    test('stored bytes are copies', () async {
      final store = MemoryBlobStore();
      final bytes = Uint8List.fromList([1]);
      await store.put('k', bytes);
      bytes[0] = 7;
      (await store.get('k'))![0] = 8;
      expect(await store.get('k'), [1]);
    });
    test('rejects invalid keys', () {
      final store = MemoryBlobStore();
      expect(() => store.put('../x', Uint8List(0)), throwsArgumentError);
      expect(() => store.get(''), throwsArgumentError);
      expect(() => store.delete('a//b'), throwsArgumentError);
    });
  });

  group('MemoryKeyValueStore', () {
    test('get/set/remove/entries', () async {
      final kv = MemoryKeyValueStore({'seed': '1'});
      expect(await kv.get('seed'), '1');
      await kv.set('a.x', '2');
      await kv.set('a.y', '3');
      await kv.remove('seed');
      await kv.remove('missing');
      expect(await kv.get('seed'), isNull);
      expect(await kv.entries(prefix: 'a.'), {'a.x': '2', 'a.y': '3'});
      expect(await kv.entries(), hasLength(2));
    });
  });

  group('FakeKartkaHttp', () {
    test('records requests and answers from the handler', () async {
      final http = FakeKartkaHttp(
        (r) => r.url.path == '/ok'
            ? FakeKartkaHttp.text('hi', headers: {'x': '1'})
            : FakeKartkaHttp.text('no', status: 404),
      );
      final ok = await http.get(
        Uri.parse('https://h/ok'),
        headers: {'Referer': 'r'},
      );
      expect(ok.body, 'hi');
      expect(ok.ok, isTrue);
      expect(ok.headers, {'x': '1'});
      final post = await http.post(Uri.parse('https://h/p'), body: 'b');
      expect(post.statusCode, 404);
      expect(post.ok, isFalse);
      expect(http.requests.map((r) => r.method), ['GET', 'POST']);
      expect(http.requests.first.headers, {'Referer': 'r'});
      expect(http.requests.last.body, 'b');
    });
    test('the default handler answers 404', () async {
      final r = await FakeKartkaHttp().get(Uri.parse('https://h/'));
      expect(r.statusCode, 404);
    });
  });

  group('fakes for pickers and OAuth', () {
    test('FakeFilePicker returns its canned files', () async {
      final file = PickedFile(
        name: 'a.cbz',
        read: () async => Uint8List.fromList([1]),
      );
      final picker = FakeFilePicker(files: [file], directory: [file]);
      expect(await picker.pickFiles(extensions: ['cbz']), [file]);
      expect(await picker.pickDirectory(), [file]);
      expect(await file.readBytes(), [1]);
      expect(picker.lastExtensions, ['cbz']);
    });
    test('FakeOAuthRedirect echoes a canned redirect', () async {
      final oauth = FakeOAuthRedirect(
        (auth) => Uri.parse('kartka://oauth#access_token=t'),
      );
      expect(oauth.redirectUri, Uri.parse('kartka://oauth'));
      final back = await oauth.authorize(Uri.parse('https://anilist.co/a'));
      expect(back.fragment, 'access_token=t');
      expect(oauth.authorized, [Uri.parse('https://anilist.co/a')]);
    });
    test('memoryPlatform wires everything', () {
      final p = memoryPlatform();
      expect(p.http, isA<FakeKartkaHttp>());
      expect(p.blobs, isA<MemoryBlobStore>());
      expect(p.kv, isA<MemoryKeyValueStore>());
      expect(p.secrets, isNot(same(p.kv)));
      expect(p.filePicker, isA<FakeFilePicker>());
      expect(p.oauth, isA<FakeOAuthRedirect>());
    });
  });
}
