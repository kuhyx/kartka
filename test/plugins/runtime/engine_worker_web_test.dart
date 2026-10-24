@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/web/plugin_worker_engine.dart';
import 'package:kartka/plugins/runtime/engine_default.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'package:kartka/plugins/runtime/plugins_feature.dart' as feature;

import 'web_services.dart';

PluginSession _session(String source) => PluginSession(
  manifest: const PluginManifest(
    id: 'w',
    name: 'W',
    version: '1',
    lang: 'en',
    baseUrl: 'https://w.test',
  ),
  source: source,
  services: WebServices(),
  engineFactory: WorkerEngine.new,
);

/// Run with `fvm flutter test --platform chrome <this file>` (headless).
void main() {
  test(
    'the whole plugins feature compiles for the web and picks the worker',
    () {
      expect(createDefaultEngine(), isA<WorkerEngine>());
      expect(feature.pluginsRoute, '/plugins');
    },
  );

  test(
    'a plugin runs in the sandboxed worker and uses the host bridge',
    () async {
      final s = _session('''
async function popular(p) {
  var r = await kartka.http.get('https://w.test/x');
  var rows = kartka.html.select(r.body, 'li a');
  await kartka.prefs.set('k', 'v');
  return { n: rows.length, body: r.body, pref: await kartka.prefs.get('k') };
}
''');
      final r = (await s.call(PluginMethod.popular, [1]))! as Map;
      expect(r['n'], 1);
      expect(r['pref'], 'v');
      await s.dispose();
    },
  );

  test('the worker has no way to the network or storage', () async {
    final s = _session('''
async function popular(p) {
  var out = {};
  delete self.fetch;
  delete self.indexedDB;
  delete self.XMLHttpRequest;
  var blob = URL.createObjectURL(new Blob(['x']));
  try { await fetch(blob); out.fetch = 'allowed'; } catch (e) { out.fetch = 'blocked'; }
  try { var q = indexedDB.open('kartka'); out.idb = 'allowed'; } catch (e) { out.idb = 'blocked'; }
  try { var x = new XMLHttpRequest(); x.open('GET', blob, false); x.send(); out.xhr = 'allowed'; } catch (e) { out.xhr = 'blocked'; }
  try { new WebSocket('wss://example.com'); out.ws = 'allowed'; } catch (e) { out.ws = 'blocked'; }
  return out;
}
''');
    final r = (await s.call(PluginMethod.popular, [1]))! as Map;
    expect(r, {
      'fetch': 'blocked',
      'idb': 'blocked',
      'xhr': 'blocked',
      'ws': 'blocked',
    });
    await s.dispose();
  });

  test(
    'dispose kills a synchronous infinite loop; the next call reboots',
    () async {
      final s = _session('''
function popular(p) { while (true) {} }
function latest(p) { return 7; }
''');
      await expectLater(
        s.call(PluginMethod.popular, [
          1,
        ], timeout: const Duration(milliseconds: 300)),
        throwsA(isA<PluginException>()),
      );
      expect(await s.call(PluginMethod.latest, [1]), 7);
      await s.dispose();
    },
  );

  test('a plugin that fails to evaluate reports the id', () async {
    final s = _session('function ( {');
    await expectLater(
      s.call(PluginMethod.popular, [1]),
      throwsA(isA<PluginException>().having((e) => e.pluginId, 'id', 'w')),
    );
  });
}
