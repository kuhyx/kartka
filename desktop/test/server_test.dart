import 'dart:io';

import 'package:kartka_desktop/src/static_files.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.start());
  tearDown(() => h.close());

  test('serves the web build with strict content types', () async {
    final index = await h.call('GET', '/', api: false);
    expect(index.status, 200);
    expect(index.headers.contentType!.mimeType, 'text/html');
    expect(text(index), contains('Kartka'));
    final wasm = await h.call('GET', '/main.wasm', api: false);
    expect(wasm.headers.contentType!.mimeType, 'application/wasm');
    expect(wasm.headers.value('x-content-type-options'), 'nosniff');
    expect((await h.call('HEAD', '/', api: false)).body, isEmpty);
    expect((await h.call('GET', '/nope.js', api: false)).status, 404);
    expect((await h.call('POST', '/', api: false)).status, 405);
  });

  test('refuses a foreign Host (DNS rebinding)', () async {
    final r = await h.call('GET', '/', api: false, host: 'evil.example');
    expect(r.status, 421);
    final local = await h.call('GET', '/', api: false, host: 'localhost');
    expect(local.status, 200);
  });

  test('refuses cross-site writes and API calls without x-kartka', () async {
    final foreign = await h.call(
      'PUT',
      '/files/a',
      headers: {'origin': 'https://evil.example'},
      body: [1],
    );
    expect(foreign.status, 403);
    final own = await h.call(
      'PUT',
      '/files/a',
      headers: {'origin': 'http://127.0.0.1:${h.server.port}'},
      body: [1],
    );
    expect(own.status, 204);
    for (final path in [
      '/files/a',
      '/files',
      '/secrets/x',
      '/proxy',
      '/oauth/result',
    ]) {
      expect((await h.call('GET', path, api: false)).status, 403, reason: path);
    }
    expect((await h.call('GET', '/oauth', api: false)).status, 200);
  });

  test('a failing handler answers 500 instead of dropping', () async {
    File('${h.dir.path}/config/kartka/secrets.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{corrupt');
    expect((await h.call('GET', '/secrets/x')).status, 500);
  });

  test('content types for every web-build asset kind', () {
    const cases = {
      'a.mjs': 'text/javascript',
      'a.json': 'application/json',
      'a.css': 'text/css',
      'a.png': 'image/png',
      'a.JPG': 'image/jpeg',
      'a.svg': 'image/svg+xml',
      'a.ico': 'image/x-icon',
      'a.ttf': 'font/ttf',
      'a.otf': 'font/otf',
      'a.woff2': 'font/woff2',
      'a.bin': 'application/octet-stream',
    };
    cases.forEach((file, mime) => expect(contentTypeFor(file).mimeType, mime));
  });

  test('never grants CORS', () async {
    final pre = await h.call(
      'OPTIONS',
      '/proxy?url=https://example.org/',
      api: false,
      headers: {'origin': 'https://evil.example'},
    );
    expect(pre.status, 403);
    expect(pre.headers.value('access-control-allow-origin'), isNull);
    final get = await h.call('GET', '/files', headers: {'origin': 'https://e'});
    expect(get.headers.value('access-control-allow-origin'), isNull);
  });
}
