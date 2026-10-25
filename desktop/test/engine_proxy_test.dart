import 'package:test/test.dart';

import 'engine_routes_test.dart' show FakeEngine;
import 'helpers.dart';
import 'proxy_test.dart' show Upstream;

void main() {
  late FakeEngine engine;
  late Harness h;
  late Upstream up;
  late List<String> logs;

  setUp(() async {
    engine = FakeEngine();
    logs = [];
    h = await Harness.start(engine: engine, log: logs.add);
    up = Upstream();
    await up.start();
  });
  tearDown(() async {
    await up.server.close(force: true);
    await h.close();
  });

  String proxied(String path) =>
      '/proxy?url=${Uri.encodeQueryComponent(up.url(path))}';

  test('engine cookies follow /proxy requests, after the page ones', () async {
    engine.cookie = 'sid=a=b; cf=1';
    await h.call('GET', proxied('/page'));
    expect(up.headers.value('cookie'), 'sid=a=b; cf=1');
    await h.call(
      'GET',
      proxied('/page'),
      headers: {'x-kartka-h-cookie': 'mine=1'},
    );
    expect(up.headers.value('cookie'), 'mine=1; sid=a=b; cf=1');
  });

  test('no engine cookies, or a failing engine, change nothing', () async {
    await h.call('GET', proxied('/page'));
    expect(up.headers.value('cookie'), isNull);
    engine.fail = StateError('engine down: sid=secret');
    final r = await h.call('GET', proxied('/page'));
    expect(r.status, 200);
    expect(up.headers.value('cookie'), isNull);
    expect(logs.single, contains('StateError'));
    expect(logs.single, isNot(contains('secret')));
  });
}
