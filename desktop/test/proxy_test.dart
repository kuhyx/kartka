import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:kartka_desktop/src/proxy.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A local upstream that records what reached it (no live network).
class Upstream {
  late HttpServer server;
  late HttpHeaders headers;
  late String method;
  late List<int> body;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      method = r.method;
      headers = r.headers;
      body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      final res = r.response;
      if (r.uri.path == '/img') {
        res.headers.contentType = ContentType('image', 'jpeg');
        res.add([0xff, 0xd8, 0x00, 0xff]);
      } else if (r.uri.path == '/missing') {
        res.statusCode = 404;
      } else {
        res.headers.set('set-cookie', 'sid=1');
        res.write('ok');
      }
      await res.close();
    });
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';
}

void main() {
  late Harness h;
  late Upstream up;
  setUp(() async {
    h = await Harness.start();
    up = Upstream();
    await up.start();
  });
  tearDown(() async {
    await up.server.close(force: true);
    await h.close();
  });

  String proxied(String url) => '/proxy?url=${Uri.encodeComponent(url)}';

  test('GET: allowed headers through, honest UA, no Via', () async {
    final r = await h.call(
      'GET',
      proxied(up.url('/page')),
      headers: {
        '${requestHeaderPrefix}referer': 'https://mangadex.org/',
        '${requestHeaderPrefix}user-agent': 'Mozilla/5.0 spoof',
        '${requestHeaderPrefix}x-mal-client-id': 'abc',
        '${requestHeaderPrefix}x-forwarded-for': '1.2.3.4',
        '${requestHeaderPrefix}dnt': '1',
      },
    );
    expect(r.status, 200);
    expect(text(r), 'ok');
    expect(up.method, 'GET');
    expect(up.headers.value('referer'), 'https://mangadex.org/');
    expect(up.headers.value('user-agent'), kartkaUserAgent);
    expect(up.headers.value('x-mal-client-id'), 'abc');
    expect(up.headers.value('x-forwarded-for'), isNull);
    expect(up.headers.value('dnt'), isNull);
    expect(up.headers.value('via'), isNull);
    expect(up.headers.value(apiHeader), isNull);
    expect(r.headers.value('${responseHeaderPrefix}set-cookie'), 'sid=1');
    expect(r.headers.value('access-control-allow-origin'), isNull);
  });

  test('PATCH: method, body and Content-Type unchanged', () async {
    final r = await h.call(
      'PATCH',
      proxied(up.url('/v2/manga/1/my_list_status')),
      headers: {
        '${requestHeaderPrefix}content-type':
            'application/x-www-form-urlencoded',
      },
      body: utf8.encode('num_chapters_read=12'),
    );
    expect(r.status, 200);
    expect(up.method, 'PATCH');
    expect(
      up.headers.contentType!.mimeType,
      'application/x-www-form-urlencoded',
    );
    expect(utf8.decode(up.body), 'num_chapters_read=12');
  });

  test('images pass through byte-exact; upstream status is kept', () async {
    final img = await h.call('GET', proxied(up.url('/img')));
    expect(img.body, [0xff, 0xd8, 0x00, 0xff]);
    expect(img.headers.contentType!.mimeType, 'image/jpeg');
    final missing = await h.call('GET', proxied(up.url('/missing')));
    expect(missing.status, 404);
  });

  test('refuses bad targets and methods', () async {
    expect((await h.call('GET', '/proxy')).status, 400);
    expect((await h.call('GET', proxied('ftp://h/x'))).status, 400);
    expect((await h.call('GET', proxied('file:///etc/passwd'))).status, 400);
    final self = 'http://127.0.0.1:${h.server.port}/proxy';
    expect((await h.call('GET', proxied(self))).status, 400);
    expect((await h.call('TRACE', proxied(up.url('/')))).status, 405);
  });

  test("an unreachable upstream is a 502 marked as the proxy's", () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final r = await h.call('GET', proxied('http://127.0.0.1:$port/'));
    expect(r.status, 502);
    expect(r.headers.value(proxyErrorHeader), isNotNull);
  });

  test('header policy', () {
    expect(ProxyRoute.forwards('referer'), isTrue);
    expect(ProxyRoute.forwards('x-api-key'), isTrue);
    expect(ProxyRoute.forwards('via'), isFalse);
    expect(ProxyRoute.forwards('x-real-ip'), isFalse);
    expect(ProxyRoute.forwards('host'), isFalse);
  });
}
