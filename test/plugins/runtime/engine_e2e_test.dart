// End to end on a REAL headless chromium (skipped when none is installed):
// a JS plugin -> KartkaHostServices -> WrapperBrowser (the app's engine loop
// and probe JS) -> the desktop wrapper, run in-process -> chromium over CDP.
// The wrapper is headless-only here: nothing can reach the live display.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/wrapper_browser.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';
import 'package:kartka/plugins/runtime/plugin_source.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka_desktop/kartka_desktop.dart';

import 'support.dart';

/// Mangayomi-style: hands the page's image count back through setResponse.
const _countScript =
    'window.flutter_inappwebview.callHandler("setResponse", '
    'String(document.querySelectorAll("#pages img").length))';

Uri page(String html) => Uri.dataFromString(html, mimeType: 'text/html');

void main() {
  if (findEngineBrowser().isEmpty) {
    test('engine end to end', () {}, skip: 'no chromium-family browser');
    return;
  }
  late Directory dir;
  late WrapperServer server;
  late IOClient client;
  late WrapperBrowser browser;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('kartka_e2e');
    File('${dir.path}/index.html').writeAsStringSync('<title>k</title>');
    server = WrapperServer(
      webRoot: dir.path,
      filesDir: '${dir.path}/data/files',
      secretsFile: '${dir.path}/secrets.json',
      log: (_) {},
    );
    await server.start(0);
    client = IOClient();
    browser = WrapperBrowser(
      client,
      Uri.parse('http://127.0.0.1:${server.port}/'),
      pollInterval: const Duration(milliseconds: 50),
    );
  });
  tearDownAll(() async {
    client.close();
    await server.stop();
    dir.deleteSync(recursive: true);
  });

  test('a plugin reads a chapter whose pages only exist after JS', () async {
    final chapter = page(fixture('site/js_chapter.html'));
    final src = PluginSource(
      PluginSession(
        manifest: const PluginManifest(
          id: 'js',
          name: 'JS',
          version: '1',
          lang: 'en',
          baseUrl: 'https://site.test',
        ),
        source: fixture('js_pages.js'),
        services: KartkaHostServices(
          pluginId: 'js',
          http: FakeKartkaHttp(),
          store: PluginStore(MemoryKeyValueStore()),
          browser: browser,
        ),
        engineFactory: QuickJsEngine.new,
      ),
    );
    final pages = await src.pages('$chapter');
    expect(pages.map((p) => p.imageUrl), [
      'https://img.example.invalid/p1.jpg',
      'https://img.example.invalid/p2.jpg',
    ]);
    await src.session.dispose();
  });

  test('resources, scripts and the Mangayomi response hook', () async {
    final r = await browser.load(
      EngineRequest(
        url: page(fixture('site/js_chapter.html')),
        waitFor: '#pages img',
        scripts: const [_countScript],
        awaitResponse: true,
      ),
    );
    expect(r.timedOut, isFalse);
    expect(r.resources, contains('https://img.example.invalid/p1.jpg'));
    expect(r.html, contains('p2.jpg'));
    // The scripts ran once the document completed, before the images came.
    expect(r.response, '0');
  });

  test(
    'a Cloudflare interstitial stops the engine: ChallengeRequired',
    () async {
      final wall = page(
        '<title>Just a moment...</title><div id="challenge-form"></div>',
      );
      await expectLater(
        browser.load(EngineRequest(url: wall, waitFor: '#never')),
        throwsA(
          isA<ChallengeRequired>().having((c) => c.kind, 'kind', 'cloudflare'),
        ),
      );
    },
  );

  test(
    'a captcha on a near-empty page is a challenge; on content not',
    () async {
      await expectLater(
        browser.load(
          EngineRequest(url: page('<div class="g-recaptcha"></div>')),
        ),
        throwsA(
          isA<ChallengeRequired>().having((c) => c.kind, 'kind', 'captcha'),
        ),
      );
      final long = 'chapter text ' * 400;
      final r = await browser.load(
        EngineRequest(url: page('<p>$long</p><div class="g-recaptcha"></div>')),
      );
      expect(r.html, contains('g-recaptcha'));
    },
  );

  test('a missed waitFor returns the snapshot as timed out', () async {
    final r = await browser.load(
      EngineRequest(
        url: page('<p>static</p>'),
        waitFor: '#never',
        timeout: const Duration(milliseconds: 600),
      ),
    );
    expect(r.timedOut, isTrue);
    expect(r.html, contains('static'));
  });
}
