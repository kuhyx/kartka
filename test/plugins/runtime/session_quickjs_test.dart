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

  test('a CPU-bound plugin cannot block the timeout', () async {
    final s = _session('''
function popular(p) {
  var end = Date.now() + 2000;
  while (Date.now() < end) {}
  return 1;
}
''');
    final sw = Stopwatch()..start();
    await expectLater(
      s.call(PluginMethod.popular, [
        1,
      ], timeout: const Duration(milliseconds: 200)),
      throwsA(isA<PluginException>()),
    );
    expect(sw.elapsedMilliseconds, lessThan(1000));
    await s.dispose();
  });

  test('bad input and isolate errors become engine_error messages', () async {
    final seen = <String>[];
    final e = QuickJsEngine();
    await e.start('function popular() {}', seen.add);
    e
      ..post('not json')
      ..debugInjectError('boom');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await e.dispose();
    expect(seen, hasLength(2));
    expect(seen, everyElement(contains('engine_error')));
    expect(seen.any((m) => m.contains('boom')), true);
  });

  test('an isolate error before start completes fails start', () async {
    final e = QuickJsEngine();
    final started = e.start('function popular() {}', (_) {});
    final check = expectLater(started, throwsA(isA<StateError>()));
    e.debugInjectError('early');
    await check;
    await e.dispose();
  });

  test(
    'dispose frees the runtime and the isolate exits without a kill',
    () async {
      final e = QuickJsEngine();
      await e.start('function popular() {}', (_) {});
      final sw = Stopwatch()..start();
      await e.dispose();
      // The kill fallback waits a full second; a clean exit is far quicker.
      expect(sw.elapsedMilliseconds, lessThan(900));
    },
  );

  test('disposing an engine that never started is a no-op', () async {
    await QuickJsEngine().dispose();
  });

  test('the inline engine starts, posts and disposes', () async {
    final seen = <String>[];
    final e = InlineQuickJsEngine();
    await e.start('function popular(p) { return p + 1; }', seen.add);
    e.post('{"t":"call","id":1,"method":"popular","args":[1]}');
    expect(seen.single, contains('"value":2'));
    await e.dispose();
  });
}
