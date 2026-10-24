import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'engine_contract.dart';
import 'support.dart';

PluginSession _session(String source) => PluginSession(
  manifest: const PluginManifest(
    id: 'q',
    name: 'Q',
    version: '1',
    lang: 'en',
    baseUrl: 'https://q.test',
  ),
  source: source,
  services: FakeServices(),
  engineFactory: QuickJsEngine.new,
);

/// QuickJS runs under plain `flutter test`: `flutter_test_config.dart`
/// preloads the Linux library that flutter_js bundles.
void main() {
  group('contract', () => engineContractTests(QuickJsEngine.new));

  test('only the kartka global is reachable', () async {
    final s = _session('''
function popular(p) {
  return [typeof fetch, typeof sendMessage, typeof setTimeout,
          typeof XMLHttpRequest, typeof require, typeof kartka.http.get];
}
function latest(p) { console.log('hi', p); return null; }
''');
    expect(await s.call(PluginMethod.popular, [1]), [
      'undefined',
      'undefined',
      'undefined',
      'undefined',
      'undefined',
      'function',
    ]);
    await s.call(PluginMethod.latest, [1]);
    await s.dispose();
  });
}
