import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/wrapper_protocol.dart';
import 'package:kartka/platform/wrapper_stores.dart';

/// A tiny in-memory stand-in for the wrapper's /files and /secrets routes.
MockClient fakeWrapper(Map<String, List<int>> files, List<http.Request> log) =>
    MockClient((r) async {
      log.add(r);
      expect(r.headers[KartkaWrapper.apiHeader], '1');
      final path = r.url.path;
      final prefix = r.url.queryParameters['prefix'];
      if (prefix != null) {
        final root = path.substring(1);
        final keys = files.keys
            .where((k) => k.startsWith('$root/$prefix'))
            .map((k) => k.substring(root.length + 1))
            .toList();
        if (root == 'secrets') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                for (final k in keys) k: utf8.decode(files['$root/$k']!),
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode(keys), 200);
      }
      final key = Uri.decodeComponent(path.substring(1));
      switch (r.method) {
        case 'PUT':
          files[key] = r.bodyBytes;
          return http.Response('', 204);
        case 'DELETE':
          files.remove(key);
          return http.Response('', 204);
        default:
          final bytes = files[key];
          return bytes == null
              ? http.Response('', 404)
              : http.Response.bytes(bytes, 200);
      }
    });

void main() {
  final base = Uri.parse('http://127.0.0.1:47391/');

  test('WrapperBlobStore round-trips through /files', () async {
    final files = <String, List<int>>{};
    final log = <http.Request>[];
    final store = WrapperBlobStore(fakeWrapper(files, log), base);
    await store.put('pages/a/1', Uint8List.fromList([1, 2]));
    expect(log.single.url.path, '/files/pages/a/1');
    expect(await store.get('pages/a/1'), [1, 2]);
    expect(await store.get('pages/a/2'), isNull);
    expect(await store.list('pages/'), ['pages/a/1']);
    await store.delete('pages/a/1');
    expect(files, isEmpty);
    expect(() => store.put('../x', Uint8List(0)), throwsArgumentError);
  });

  test('WrapperKeyValueStore round-trips through /secrets', () async {
    final files = <String, List<int>>{};
    final store = WrapperKeyValueStore(fakeWrapper(files, []), base);
    await store.set('anilist.token', 'tok ż');
    expect(await store.get('anilist.token'), 'tok ż');
    expect(await store.get('mal.token'), isNull);
    await store.set('mal.token', 'm');
    expect(await store.entries(prefix: 'anilist.'), {'anilist.token': 'tok ż'});
    await store.remove('anilist.token');
    expect(await store.entries(), {'mal.token': 'm'});
    expect(() => store.set('a/b', 'x'), throwsArgumentError);
  });

  test('a wrapper error surfaces as an exception', () async {
    final failing = MockClient((_) async => http.Response('', 500));
    final store = WrapperBlobStore(failing, base);
    await expectLater(store.get('a'), throwsA(isA<WrapperException>()));
    await expectLater(
      store.put('a', Uint8List(0)),
      throwsA(isA<WrapperException>()),
    );
    final kv = WrapperKeyValueStore(failing, base);
    await expectLater(kv.entries(), throwsA(isA<WrapperException>()));
    expect(
      const WrapperException('GET', '/x', 500).toString(),
      contains('500'),
    );
  });
}
