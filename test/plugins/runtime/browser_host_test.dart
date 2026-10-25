import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/host_dispatch.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_challenge.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';
import 'package:kartka/plugins/runtime/plugin_source.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

const _manifest = PluginManifest(
  id: 'js',
  name: 'JS',
  version: '1',
  lang: 'en',
  baseUrl: 'https://site.test',
);

/// The rendered DOM of `site/js_chapter.html` after its script ran.
const _rendered =
    '<html><body><div id="pages"> '
    '<img src="https://img.example.invalid/p1.jpg"> '
    '<img src="https://img.example.invalid/p2.jpg"></div></body></html>';

KartkaHostServices services(FakeBrowser browser, [FakeKartkaHttp? http]) =>
    KartkaHostServices(
      pluginId: 'js',
      http: http ?? FakeKartkaHttp(),
      store: PluginStore(MemoryKeyValueStore()),
      browser: browser,
    );

PluginSource source(String js, PluginHostServices s) => PluginSource(
  PluginSession(
    manifest: _manifest,
    source: js,
    services: s,
    engineFactory: QuickJsEngine.new,
  ),
);

void main() {
  final chapter = Uri.parse('https://site.test/c/1');

  test('a JS-built page list reads through the engine', () async {
    final browser = FakeBrowser(
      onLoad: (r) async => EngineResult(url: r.url, html: _rendered),
    );
    final src = source(fixture('js_pages.js'), services(browser));
    final pages = await src.pages('$chapter');
    expect(pages.map((p) => p.imageUrl), [
      'https://img.example.invalid/p1.jpg',
      'https://img.example.invalid/p2.jpg',
    ]);
    expect(pages.first.headers, {'Referer': '$chapter'});
    expect(src.webViewUrl, Uri.parse('https://site.test'));
    final req = browser.loads.single;
    expect(req.url, chapter);
    expect(req.waitFor, '#pages img');
    expect(req.timeout, const Duration(seconds: 15));
    await src.session.dispose();
  });

  test('an engine challenge reaches the caller typed', () async {
    final browser = FakeBrowser(
      onLoad: (r) async => throw ChallengeRequired(r.url, 'cloudflare'),
    );
    final src = source(fixture('js_pages.js'), services(browser));
    await expectLater(
      src.pages('$chapter'),
      throwsA(
        isA<PluginChallengeException>()
            .having((e) => e.url, 'url', chapter)
            .having((e) => e.kind, 'kind', 'cloudflare')
            .having((e) => e.pluginId, 'plugin', 'js'),
      ),
    );
    await src.session.dispose();
  });

  test('a challenge survives a plugin that re-wraps the error', () async {
    final http = FakeKartkaHttp(
      (_) =>
          FakeKartkaHttp.text('<title>Just a moment...</title>', status: 503),
    );
    final src = source('''
async function popular(p) {
  try { await kartka.http.get('https://site.test/'); }
  catch (e) { throw new Error('site broke: ' + e.message); }
}
''', services(FakeBrowser(), http));
    await expectLater(
      src.popular(1),
      throwsA(
        isA<ChallengeRequired>()
            .having((e) => e.kind, 'kind', 'cloudflare')
            .having((e) => '$e', 'text', contains('site broke')),
      ),
    );
    await src.session.dispose();
  });

  test('the error text alone is enough to recover the challenge', () {
    final e = challengeFromMessage(
      'js',
      'Error: x ChallengeRequired(captcha, https://a.test/q?x=1) y',
      PluginMethod.pages,
    );
    expect(e!.url, Uri.parse('https://a.test/q?x=1'));
    expect(e.kind, 'captcha');
    expect(e.method, PluginMethod.pages);
    expect(challengeFromMessage('js', 'plain failure', null), isNull);
  });

  test('browser.load dispatch type-checks its options', () async {
    final browser = FakeBrowser(
      onLoad: (r) async =>
          EngineResult(url: r.url, html: '<p/>', response: 'r'),
    );
    final d = HostDispatcher(services(browser));
    final out = await d.dispatch('browser.load', [
      'https://site.test/a',
      {
        'headers': {'Referer': 'x'},
        'scripts': ['a()', 3],
        'waitFor': '#x',
        'awaitResponse': true,
        'timeoutMs': 1500,
      },
    ]);
    expect((out! as Map)['response'], 'r');
    final r = browser.loads.single;
    expect(r.headers, {'Referer': 'x'});
    expect(r.scripts, ['a()', '3']);
    expect(r.waitFor, '#x');
    expect(r.awaitResponse, isTrue);
    expect(r.timeout, const Duration(milliseconds: 1500));
    await d.dispatch('browser.load', ['https://site.test/b', 'junk']);
    expect(browser.loads.last.scripts, isEmpty);
    expect(browser.loads.last.timeout, EngineRequest.defaultTimeout);
    await expectLater(
      d.dispatch('browser.load', ['file:///etc/passwd']),
      throwsArgumentError,
    );
  });

  test('plain http challenges throw; ordinary errors do not', () async {
    final http = FakeKartkaHttp(
      (r) => r.url.path == '/cf'
          ? FakeKartkaHttp.text('', headers: {'cf-mitigated': 'challenge'})
          : FakeKartkaHttp.text('Forbidden', status: 403),
    );
    final s = services(FakeBrowser(), http);
    await expectLater(
      s.httpPost('https://site.test/cf'),
      throwsA(isA<ChallengeRequired>()),
    );
    expect((await s.httpGet('https://site.test/x')).status, 403);
  });

  test('without a browser the host call reports it unavailable', () async {
    final s = KartkaHostServices(
      pluginId: 'js',
      http: FakeKartkaHttp(),
      store: PluginStore(MemoryKeyValueStore()),
    );
    await expectLater(
      s.browserLoad('https://site.test/'),
      throwsA(isA<EngineUnavailable>()),
    );
  });
}
