import 'dart:io';

import 'package:kartka_desktop/src/engine.dart';
import 'package:test/test.dart';

import 'chromium_unit_test.dart' show script;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_window'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('no browser: 503 for pages and windows, no cookies', () async {
    final host = ChromiumEngineHost(
      exe: '',
      profile: '${dir.path}/p',
      hosts: EngineHosts('${dir.path}/h.json')..add('a.test'),
      headlessOnly: false,
    );
    await expectLater(host.createPage(), throwsA(isA<EngineError>()));
    await expectLater(
      host.open(Uri.parse('https://a.test/')),
      throwsA(isA<EngineError>()),
    );
    expect(await host.cookieHeader(Uri.parse('https://a.test/')), isNull);
    await host.closePage('p9');
    await expectLater(
      host.navigate('p9', Uri.parse('https://a.test/'), {}),
      throwsA(isA<EngineError>().having((e) => e.status, 'status', 404)),
    );
    await host.stop();
    expect('${const EngineError(1, 'x')}', 'EngineError(1, x)');
  });

  test(
    'the window blocks the engine until finish registers the host',
    () async {
      final exe = script(dir, 'window', "trap 'exit 0' TERM\nsleep 30 &\nwait");
      final hosts = EngineHosts('${dir.path}/h.json');
      final host = ChromiumEngineHost(
        exe: exe,
        profile: '${dir.path}/p',
        hosts: hosts,
        headlessOnly: false,
      );
      final url = Uri.parse('https://site.test/login');
      await host.open(url);
      await host.open(url); // Reopening replaces the first window.
      await expectLater(
        host.createPage(),
        throwsA(
          isA<EngineError>().having((e) => e.code, 'code', 'window-open'),
        ),
      );
      expect(await host.cookieHeader(url), isNull);
      await host.finish(url);
      expect(hosts.covers(url), isTrue);
      await host.stop();
    },
  );

  test('while the window opens, nothing relaunches headless', () async {
    final exe = script(dir, 'slow', "trap 'exit 0' TERM\nsleep 30 &\nwait");
    final host = ChromiumEngineHost(
      exe: exe,
      profile: '${dir.path}/p',
      hosts: EngineHosts('${dir.path}/h.json')..add('site.test'),
      headlessOnly: false,
    );
    final url = Uri.parse('https://site.test/');
    final opening = host.open(url);
    await expectLater(
      host.createPage(),
      throwsA(isA<EngineError>().having((e) => e.code, 'code', 'window-open')),
    );
    expect(await host.cookieHeader(url), isNull);
    await opening;
    await host.stop();
  });

  test('a window kuhy closed himself stops blocking the engine', () async {
    final exe = script(dir, 'gone', 'exit 0');
    final host = ChromiumEngineHost(
      exe: exe,
      profile: '${dir.path}/p',
      hosts: EngineHosts('${dir.path}/h.json'),
      headlessOnly: false,
    );
    await host.open(Uri.parse('https://site.test/'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // The fake exe is no browser: launching fails, but not as window-open.
    await expectLater(host.createPage(), throwsA(isA<StateError>()));
    await expectLater(host.createPage(), throwsA(isA<StateError>()));
  });

  test('headless-only refuses the window', () async {
    final host = ChromiumEngineHost(
      exe: '/bin/true',
      profile: '${dir.path}/p',
      hosts: EngineHosts('${dir.path}/h.json'),
      headlessOnly: true,
    );
    await expectLater(
      host.open(Uri.parse('https://a.test/')),
      throwsA(
        isA<EngineError>().having((e) => e.code, 'code', 'headless-only'),
      ),
    );
  });
}
