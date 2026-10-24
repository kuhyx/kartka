import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'engine_contract.dart';
import 'support.dart';

/// Needs flutter_js's bundled Linux library; run via
/// `test/plugins/runtime/run_quickjs_test.sh`. Skipped otherwise.
final _hasLib = Platform.environment['LIBQUICKJSC_TEST_PATH'] != null;

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

void main() {
  if (!_hasLib) {
    test('QuickJS engine', () {}, skip: 'LIBQUICKJSC_TEST_PATH not set');
    return;
  }
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
