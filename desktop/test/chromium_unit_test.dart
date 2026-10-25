import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/chromium.dart';
import 'package:kartka_desktop/src/engine.dart';
import 'package:test/test.dart';

/// A fake "browser": a shell script in a temp dir.
String script(Directory dir, String name, String body) {
  final f = File('${dir.path}/$name')..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['+x', f.path]);
  return f.path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_engine'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('engine browser: override, then /usr/bin/chromium, then the list', () {
    expect(
      findEngineBrowser(
        env: {'KARTKA_ENGINE_BROWSER': '/x'},
        exists: (_) => true,
      ),
      '/x',
    );
    expect(
      findEngineBrowser(env: {}, exists: (p) => p == '/usr/bin/chromium'),
      '/usr/bin/chromium',
    );
    expect(
      findEngineBrowser(env: {}, exists: (p) => p == '/usr/bin/brave'),
      '/usr/bin/brave',
    );
    expect(findEngineBrowser(env: {}, exists: (_) => false), '');
  });

  test('headless runs without a display; the window is an app window', () {
    expect(
      headlessEnvironment({
        'DISPLAY': ':0',
        'WAYLAND_DISPLAY': 'w',
        'HOME': '/h',
      }),
      {'HOME': '/h'},
    );
    expect(
      headlessArgs('/p'),
      containsAll(['--headless=new', '--user-data-dir=/p']),
    );
    expect(
      windowArgs('/p', Uri.parse('https://a.test/')),
      containsAll(['--app=https://a.test/', '--user-data-dir=/p']),
    );
    expect(
      windowArgs('/p', Uri.parse('https://a.test/')),
      isNot(contains('--headless=new')),
    );
  });

  test('cookieHeaderFor applies domain, path, secure and expiry', () {
    final now = DateTime.utc(2026, 10, 25);
    final soon = now.millisecondsSinceEpoch / 1000 + 60;
    final cookies = [
      {'name': 'host', 'value': '1', 'domain': 'site.test', 'path': '/'},
      {'name': 'dom', 'value': 'a=b', 'domain': '.site.test', 'path': '/'},
      {
        'name': 'sec',
        'value': '1',
        'domain': 'site.test',
        'path': '/',
        'secure': true,
      },
      {'name': 'deep', 'value': '1', 'domain': 'site.test', 'path': '/m'},
      {
        'name': 'old',
        'value': '1',
        'domain': 'site.test',
        'path': '/',
        'expires': 1,
      },
      {
        'name': 'live',
        'value': '1',
        'domain': 'site.test',
        'path': '/',
        'expires': soon,
      },
      {'name': 'other', 'value': '1', 'domain': 'evilsite.test', 'path': '/'},
      'junk',
    ];
    expect(
      cookieHeaderFor(Uri.parse('https://site.test/m/1'), cookies, now),
      'host=1; dom=a=b; sec=1; deep=1; live=1',
    );
    expect(
      cookieHeaderFor(Uri.parse('http://img.site.test/mx'), cookies, now),
      'dom=a=b',
    );
    expect(
      cookieHeaderFor(Uri.parse('http://site.test'), [cookies[3]], now),
      '',
    );
  });

  test('registered hosts persist at 0600 and survive corruption', () {
    final path = '${dir.path}/d/engine-hosts.json';
    EngineHosts(path)
      ..add('Site.test')
      ..add('site.test');
    final again = EngineHosts(path);
    expect(again.covers(Uri.parse('https://img.site.test/')), isTrue);
    expect(again.covers(Uri.parse('https://evilsite.test/')), isFalse);
    expect(jsonDecode(File(path).readAsStringSync()), ['site.test']);
    expect(File(path).statSync().modeString(), 'rw-------');
    File(path).writeAsStringSync('{oops');
    expect(EngineHosts(path).covers(Uri.parse('https://site.test/')), isFalse);
  });

  test('a browser that never opens DevTools is refused', () async {
    final exe = script(dir, 'dead', 'exit 0');
    await expectLater(
      HeadlessChromium.launch(exe, '${dir.path}/profile'),
      throwsA(isA<StateError>()),
    );
  });

  test('a browser that is not headless is refused and killed', () async {
    final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake.listen((r) async {
      r.response.write(jsonEncode({'User-Agent': 'Mozilla/5.0 Chrome/156'}));
      await r.response.close();
    });
    addTearDown(() => fake.close(force: true));
    final profile = '${dir.path}/profile';
    Directory(profile).createSync();
    File('$profile/DevToolsActivePort').writeAsStringSync('stale\n');
    final exe = script(dir, 'windowed', '''
for a in "\$@"; do case "\$a" in --user-data-dir=*) p="\${a#*=}";; esac; done
printf '%s\\n/devtools/browser/x\\n' ${fake.port} > "\$p/DevToolsActivePort"
exec sleep 30''');
    await expectLater(
      HeadlessChromium.launch(exe, profile),
      throwsA(
        isA<StateError>().having((e) => '$e', 'msg', contains('headless')),
      ),
    );
  });

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
