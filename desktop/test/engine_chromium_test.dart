// Drives a REAL headless chromium (skipped when none is installed). Never
// touches the live display: the engine runs without DISPLAY, and these
// hosts are headless-only.
import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/chromium.dart';
import 'package:kartka_desktop/src/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final String _exe = findEngineBrowser();

/// The fixture chapter: its page list only exists after its script runs.
final _chapter = Uri.dataFromString('''
<div id="pages"></div>
<script>
setTimeout(function () {
  ['p1.jpg', 'p2.jpg'].forEach(function (n) {
    var i = document.createElement('img');
    i.src = 'https://img.example.invalid/' + n;
    document.getElementById('pages').appendChild(i);
  });
}, 200);
</script>''', mimeType: 'text/html');

Future<Object?> until(
  Future<Object?> Function() probe,
  bool Function(Object?) done,
) async {
  for (var i = 0; i < 100; i++) {
    final v = await probe();
    if (done(v)) return v;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('condition never held');
}

void main() {
  if (_exe.isEmpty) {
    test('chromium engine', () {}, skip: 'no chromium-family browser');
    return;
  }
  late Directory dir;
  late ChromiumEngineHost host;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('kartka_chromium');
    host = ChromiumEngineHost(
      exe: _exe,
      profile: '${dir.path}/engine-profile',
      hosts: EngineHosts('${dir.path}/engine-hosts.json'),
      headlessOnly: true,
      maxPages: 2,
      allowLoopback: true,
    );
  });
  tearDownAll(() async {
    await host.stop();
    dir.deleteSync(recursive: true);
  });

  test('a JS-built page list is readable after its script ran', () async {
    final id = await host.createPage();
    await host.navigate(id, _chapter, {'X-Test': '1', 'User-Agent': 'no'});
    final count = await until(
      () => host.evaluate(id, "document.querySelectorAll('#pages img').length"),
      (v) => v == 2,
    );
    expect(count, 2);
    final html = await host.evaluate(id, 'document.documentElement.outerHTML');
    expect(html, contains('https://img.example.invalid/p2.jpg'));
    expect(
      await host.evaluate(id, 'navigator.userAgent'),
      contains('Headless'),
    );
    expect(await host.evaluate(id, 'Promise.resolve(41 + 1)'), 42);
    await expectLater(
      host.evaluate(id, 'throw new Error("page broke")'),
      throwsA(
        isA<EngineError>().having(
          (e) => e.code,
          'code',
          contains('page broke'),
        ),
      ),
    );
    await host.closePage(id);
  });

  test('failed navigations and evicted pages are refused', () async {
    final a = await host.createPage();
    await expectLater(
      host.navigate(a, Uri.parse('http://127.0.0.1:1/'), {
        'Referer': 'https://r.test/',
      }),
      throwsA(isA<EngineError>().having((e) => e.status, 'status', 502)),
    );
    final b = await host.createPage();
    await host.createPage(); // maxPages 2: evicts a.
    await expectLater(host.evaluate(a, '1'), throwsA(isA<EngineError>()));
    expect(await host.evaluate(b, '1 + 1'), 2);
  });

  test('cookies set in the profile follow its registered hosts', () async {
    final site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => site.close(force: true));
    site.listen((r) async {
      r.response.headers.add('set-cookie', 'sid=a=b; Max-Age=3600; Path=/');
      r.response.headers.contentType = ContentType.html;
      r.response.write('<p>logged in</p>');
      await r.response.close();
    });
    final url = Uri.parse('http://127.0.0.1:${site.port}/login');
    final id = await host.createPage();
    await host.navigate(id, url, {});
    await until(
      () => host.evaluate(id, 'document.readyState'),
      (v) => v == 'complete',
    );
    expect(await host.cookieHeader(url), isNull); // Not registered yet.
    await host.finish(url);
    expect(await host.cookieHeader(url), 'sid=a=b');
    expect(await host.cookieHeader(url.replace(path: '/c/1')), 'sid=a=b');
  });

  test('a browser that dies is relaunched; a dead one still stops', () async {
    final profile = '${dir.path}/crash-profile';
    final crashy = ChromiumEngineHost(
      exe: _exe,
      profile: profile,
      hosts: EngineHosts('${dir.path}/crash-hosts.json'),
      headlessOnly: true,
    );
    Future<void> crash() async {
      Process.runSync('pkill', ['-KILL', '-f', 'user-data-dir=$profile']);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    final stale = await crashy.createPage();
    await crash();
    await crashy.closePage(stale); // Its browser is gone: ignored.
    final fresh = await crashy.createPage(); // Relaunches.
    expect(await crashy.evaluate(fresh, '6 * 7'), 42);
    await crash();
    await crashy.stop();
  });

  test('pages never land on loopback, not even by a redirect', () async {
    var hits = 0;
    final site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => site.close(force: true));
    site.listen((r) async {
      hits++;
      r.response.write('<p>wrapper</p>');
      await r.response.close();
    });
    final target = 'http://127.0.0.1:${site.port}/secrets/x';
    final jump = Uri.dataFromString(
      '<script>location.href = "$target";</script>',
      mimeType: 'text/html',
    );
    Future<void> tryJump(ChromiumEngineHost on) async {
      final id = await on.createPage();
      await on.navigate(id, jump, {});
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(
        await on.evaluate(id, 'document.body.innerText'),
        isNot('wrapper'),
      );
      await on.closePage(id);
    }

    // A protected port (a wrapper's own) is blocked even where tests allow
    // loopback; without that allowance every loopback host is.
    host.protectedPorts.add(site.port);
    await tryJump(host);
    final strict = ChromiumEngineHost(
      exe: _exe,
      profile: '${dir.path}/strict-profile',
      hosts: EngineHosts('${dir.path}/strict-hosts.json'),
      headlessOnly: true,
    );
    addTearDown(strict.stop);
    await tryJump(strict);
    expect(hits, 0);
  });

  test('through the wrapper routes', () async {
    final h = await Harness.start(allowLoopbackEngine: true);
    addTearDown(h.close);
    Future<Object?> post(String path, Object body) async {
      final r = await h.call('POST', path, body: utf8.encode(jsonEncode(body)));
      return r.body.isEmpty ? r.status : jsonDecode(text(r));
    }

    final id = ((await post('/engine/page', {}))! as Map)['id'];
    expect(await post('/engine/page/$id/navigate', {'url': '$_chapter'}), 204);
    final v = await until(
      () => post('/engine/page/$id/evaluate', {
        'expression': "document.querySelectorAll('#pages img').length",
      }),
      (v) => v is Map && v['value'] == 2,
    );
    expect(v, {'value': 2});
    expect((await h.call('DELETE', '/engine/page/$id')).status, 204);
  });
}
