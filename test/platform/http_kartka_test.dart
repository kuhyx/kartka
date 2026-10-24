import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/http_kartka.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

void main() {
  group('DirectKartkaHttp', () {
    test('sends method, headers, body; forces the Kartka UA', () async {
      late http.BaseRequest seen;
      late String seenBody;
      final client = MockClient((r) async {
        seen = r;
        seenBody = r.body;
        return http.Response('ok', 201, headers: {'x-a': '1'});
      });
      final kh = DirectKartkaHttp(client);
      final r = await kh.send(
        'PATCH',
        Uri.parse('https://api.myanimelist.net/v2/x'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 spoof',
        },
        body: 'num_chapters_read=3',
      );
      expect(seen.method, 'PATCH');
      expect(seen.headers['user-agent'], kartkaUserAgent);
      expect(seen.headers['content-type'], 'application/x-www-form-urlencoded');
      expect(seenBody, 'num_chapters_read=3');
      expect(r.statusCode, 201);
      expect(r.body, 'ok');
      expect(r.headers['x-a'], '1');
    });

    test('get without a body sends none', () async {
      final client = MockClient((r) async {
        expect(r.method, 'GET');
        expect(r.bodyBytes, isEmpty);
        return http.Response('', 204);
      });
      expect(
        (await DirectKartkaHttp(client).get(Uri.parse('http://h/'))).ok,
        isTrue,
      );
    });

    test('refuses other methods and schemes', () async {
      final kh = DirectKartkaHttp(
        MockClient((_) async => http.Response('', 200)),
      );
      await expectLater(
        kh.send('TRACE', Uri.parse('https://h/')),
        throwsArgumentError,
      );
      await expectLater(
        kh.get(Uri.parse('file:///etc/passwd')),
        throwsArgumentError,
      );
    });
  });

  group('ProxyKartkaHttp', () {
    test('wraps the request for the desktop /proxy', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(
          'img',
          200,
          headers: {
            '${KartkaWrapper.responseHeaderPrefix}content-type': 'image/jpeg',
            '${KartkaWrapper.responseHeaderPrefix}set-cookie': 'a=b',
            'content-type': 'image/jpeg',
          },
        );
      });
      final kh = ProxyKartkaHttp(client, Uri.parse('http://127.0.0.1:8791/'));
      final r = await kh.post(
        Uri.parse('https://uploads.mangadex.org/a?b=c'),
        headers: {'Referer': 'https://mangadex.org/', 'Content-Type': 'text/x'},
        body: 'ż',
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, KartkaWrapper.proxyPath);
      expect(
        seen.url.queryParameters['url'],
        'https://uploads.mangadex.org/a?b=c',
      );
      expect(seen.headers[KartkaWrapper.apiHeader], '1');
      expect(
        seen.headers['${KartkaWrapper.requestHeaderPrefix}referer'],
        'https://mangadex.org/',
      );
      expect(
        seen.headers['${KartkaWrapper.requestHeaderPrefix}content-type'],
        'text/x',
      );
      expect(utf8.decode(seen.bodyBytes), 'ż');
      expect(r.body, 'img');
      expect(r.headers, {'content-type': 'image/jpeg', 'set-cookie': 'a=b'});
    });

    test('refuses non-http(s) before reaching the wrapper', () async {
      final kh = ProxyKartkaHttp(
        MockClient((_) async => fail('must not send')),
        Uri.parse('http://127.0.0.1:8791/'),
      );
      await expectLater(kh.get(Uri.parse('ftp://h/')), throwsArgumentError);
    });
  });

  test('wrapper protocol constants are what desktop/ serves', () {
    // Keep in step with desktop/lib/src/protocol.dart (separate package).
    expect(KartkaWrapper.port, 8791);
    expect(KartkaWrapper.apiHeader, 'x-kartka');
    expect(KartkaWrapper.requestHeaderPrefix, 'x-kartka-h-');
    expect(KartkaWrapper.responseHeaderPrefix, 'x-kartka-r-');
    expect(KartkaWrapper.proxyPath, '/proxy');
    expect(KartkaWrapper.filesPath, '/files');
    expect(KartkaWrapper.secretsPath, '/secrets');
    expect(KartkaWrapper.oauthPath, '/oauth');
    expect(KartkaWrapper.oauthResultPath, '/oauth/result');
  });
}
