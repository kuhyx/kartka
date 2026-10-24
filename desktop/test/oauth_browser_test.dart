import 'dart:io';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('oauth', () {
    late Harness h;
    setUp(() async => h = await Harness.start());
    tearDown(() => h.close());

    test('the page posts its URL into a one-shot slot', () async {
      final page = await h.call('GET', '/oauth?code=1', api: false);
      expect(page.headers.contentType!.mimeType, 'text/html');
      expect(text(page), contains('location.href'));
      expect((await h.call('POST', '/oauth')).status, 405);
      expect((await h.call('GET', '/oauth/result')).status, 204);
      final url = 'http://127.0.0.1:${h.server.port}/oauth#access_token=t';
      final post = await h.call('POST', '/oauth/result', body: url.codeUnits);
      expect(post.status, 204);
      final got = await h.call('GET', '/oauth/result');
      expect(got.status, 200);
      expect(text(got), url);
      expect((await h.call('GET', '/oauth/result')).status, 204);
      await h.call('POST', '/oauth/result', body: url.codeUnits);
      expect((await h.call('DELETE', '/oauth/result')).status, 204);
      expect((await h.call('GET', '/oauth/result')).status, 204);
      expect((await h.call('PUT', '/oauth/result')).status, 405);
    });

    test('only redirects to this server are accepted', () async {
      final evil = 'https://evil.example/oauth'.codeUnits;
      expect((await h.call('POST', '/oauth/result', body: evil)).status, 400);
      final local = 'http://localhost:${h.server.port}/oauth?code=c';
      final ok = await h.call('POST', '/oauth/result', body: local.codeUnits);
      expect(ok.status, 204);
    });
  });

  group('browser', () {
    test('finds the override first, else the known paths', () {
      expect(
        findBrowser(override: '/x/chrome', exists: (_) => true),
        '/x/chrome',
      );
      expect(
        findBrowser(override: '', exists: (p) => p.contains('thorium')),
        '/opt/thorium-browser/thorium-browser',
      );
      expect(findBrowser(override: '', exists: (_) => false), '');
    });

    test('opens 127.0.0.1:47391 in a fixed profile with WM class kartka', () {
      final args = browserArgs('/home/u');
      expect(args, contains('--app=http://127.0.0.1:47391'));
      expect(
        args,
        contains('--user-data-dir=/home/u/.local/share/kartka-desktop/profile'),
      );
      expect(args, contains('--class=kartka'));
    });

    test('a quick exit is a handoff; no browser is reported', () async {
      final quick = await launchBrowser(
        '/home/u',
        browser: '/bin/true',
        start: (exe, args) => Process.start(exe, const []),
      );
      expect(quick, isFalse);
      expect(await launchBrowser('/home/u', browser: ''), isFalse);
      // Default Process.start on a binary that ignores its arguments and
      // exits at once: exercises the real path without opening any window.
      expect(await launchBrowser('/home/u', browser: '/bin/true'), isFalse);
    });

    test(
      'with no browser given it looks one up (fake start: no window)',
      () async {
        String? launched;
        await launchBrowser(
          '/home/u',
          start: (exe, args) {
            launched = exe;
            return Process.start('/bin/true', const []);
          },
        );
        expect(launched, findBrowser());
      },
      skip: findBrowser().isEmpty ? 'no browser on this machine' : null,
    );

    test('defaults: environment override and a real file check', () {
      expect(findBrowser(override: '/bin/sh'), '/bin/sh');
      expect(findBrowser(), isA<String>());
    });
  });
}
