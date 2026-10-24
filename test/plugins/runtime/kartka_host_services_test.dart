import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

void main() {
  late FakeHttp http;
  late MemoryKeyValueStore kv;
  late List<String> logs;
  late KartkaHostServices s;

  setUp(() {
    http = FakeHttp();
    kv = MemoryKeyValueStore();
    logs = [];
    s = KartkaHostServices(
      pluginId: 'demo',
      http: http.client,
      store: PluginStore(kv),
      onLog: (id, m) => logs.add('$id: $m'),
    );
  });

  test('http goes through KartkaHttp and maps the response', () async {
    final r = await s.httpGet('https://demo.test/m/1');
    expect(r.status, 200);
    expect(r.headers['content-type'], 'text/html');
    expect(r.body, contains('One Piece'));
    final p = await s.httpPost('https://demo.test/m/1', body: 'a=1');
    expect(p.status, 200);
    expect(http.requested, [
      'GET https://demo.test/m/1',
      'POST https://demo.test/m/1',
    ]);
  });

  test('only absolute http(s) urls are allowed', () async {
    for (final bad in [
      'file:///etc/passwd',
      'javascript:1',
      '/relative',
      ':',
    ]) {
      await expectLater(s.httpGet(bad), throwsArgumentError);
      await expectLater(s.httpPost(bad), throwsArgumentError);
    }
    expect(http.requested, isEmpty);
  });

  test('html, log and prefs are scoped to the plugin', () async {
    expect(s.htmlSelect('<p>x</p>', 'p').single.text, 'x');
    s.log('hello');
    expect(logs, ['demo: hello']);
    await s.prefsSet('k', 'v');
    expect(await s.prefsGet('k'), 'v');
    expect((await kv.entries()).keys.single, 'plugins.prefs.demo.k');
    KartkaHostServices(
      pluginId: 'o',
      http: http.client,
      store: PluginStore(kv),
    ).log('x');
  });
}
