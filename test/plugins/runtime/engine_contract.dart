import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'support.dart';

/// Behaviour every engine must show when driven through [PluginSession].
void engineContractTests(JsEngineFactory factory) {
  late FakeServices services;
  late PluginSession session;

  setUp(() {
    services = FakeServices();
    session = PluginSession(
      manifest: const PluginManifest(
        id: 'demo',
        name: 'Demo',
        version: '1.0.0',
        lang: 'en',
        baseUrl: 'https://demo.test',
      ),
      source: fixture('demo.js'),
      services: services,
      engineFactory: factory,
    );
  });
  tearDown(() => session.dispose());

  test('popular runs the real sample plugin end to end', () async {
    final r = await session.call(PluginMethod.popular, [1]);
    final page = r! as Map<String, Object?>;
    final items = (page['items']! as List).cast<Map<String, Object?>>();
    expect(items.map((i) => i['title']), ['One Piece', 'Berserk']);
    expect(items.first['url'], '/m/1');
    expect(items.first['coverUrl'], 'https://demo.test/c/1.jpg');
    expect(page['hasNext'], true);
  });

  test('all six entry points return section 1 shapes', () async {
    final latest = await session.call(PluginMethod.latest, [1]);
    expect((latest! as Map)['hasNext'], false);
    final found = await session.call(PluginMethod.search, ['bers erk', 1]);
    expect(((found! as Map)['items']! as List).length, 1);
    final d = await session.call(PluginMethod.details, ['/m/1']);
    expect((d! as Map)['genres'], ['Adventure', 'Comedy']);
    expect((d as Map)['title'], 'One Piece');
    final ch = await session.call(PluginMethod.chapters, ['/m/1']);
    expect((ch! as List).map((c) => (c as Map)['number']), [2, 1.5]);
    final pg = await session.call(PluginMethod.pages, ['/m/1/c/1']);
    expect(((pg! as List).first as Map)['headers'], {
      'Referer': 'https://demo.test/',
    });
  });

  test('prefs persist across calls and log reaches the host', () async {
    await session.call(PluginMethod.pages, ['/m/1/c/1']);
    await session.call(PluginMethod.pages, ['/m/1/c/1']);
    expect(services.prefs['seen'], '2');
    await session.call(PluginMethod.details, ['/m/1']);
    expect(services.logs, ['details /m/1']);
  });

  test('plugin errors name the plugin and method', () async {
    final bad = PluginSession(
      manifest: session.manifest,
      source: 'function popular(p) { throw new Error("kaput"); }',
      services: services,
      engineFactory: factory,
    );
    await expectLater(
      bad.call(PluginMethod.popular, [1]),
      throwsA(
        isA<PluginException>()
            .having((e) => e.pluginId, 'id', 'demo')
            .having((e) => e.toString(), 'text', contains('kaput')),
      ),
    );
    await expectLater(
      bad.call(PluginMethod.search, ['x', 1]),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'msg',
          contains('does not define search'),
        ),
      ),
    );
    await bad.dispose();
  });

  test('a broken plugin source fails to load with the id', () async {
    final bad = PluginSession(
      manifest: session.manifest,
      source: 'function ( {',
      services: services,
      engineFactory: factory,
    );
    await expectLater(
      bad.call(PluginMethod.popular, [1]),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'msg',
          contains('failed to load'),
        ),
      ),
    );
  });

  test('host errors reach the plugin as rejected promises', () async {
    final s = PluginSession(
      manifest: session.manifest,
      source: '''
async function popular(p) {
  try { await kartka.html.select('<a/>', 'a[[['); } catch (e) { return e.message; }
  return 'no error';
}
''',
      services: services,
      engineFactory: factory,
    );
    expect(await s.call(PluginMethod.popular, [1]), contains('bad CSS'));
    await s.dispose();
  });

  test('timeout fails the call and the engine restarts', () async {
    services.delay = const Duration(milliseconds: 300);
    await expectLater(
      session.call(PluginMethod.popular, [
        1,
      ], timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'msg',
          contains('timed out'),
        ),
      ),
    );
    services.delay = null;
    final r = await session.call(PluginMethod.popular, [1]);
    expect(((r! as Map)['items']! as List).length, 2);
  });

  test('cancel token abandons the call', () async {
    services.delay = const Duration(milliseconds: 200);
    final token = PluginCancelToken();
    final f = session.call(PluginMethod.popular, [1], cancel: token);
    final check = expectLater(
      f,
      throwsA(
        isA<PluginException>().having((e) => e.message, 'm', 'cancelled'),
      ),
    );
    token.cancel();
    expect(token.isCancelled, true);
    await check;
  });
}
