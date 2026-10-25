import 'dart:convert';

import 'package:kartka_desktop/src/cdp.dart';
import 'package:kartka_desktop/src/engine.dart';
import 'package:kartka_desktop/src/engine_routes.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Records every call; [fail] makes the next call throw it.
class FakeEngine implements EngineHost {
  final calls = <String>[];
  Object? fail;
  String? cookie;

  void _maybeFail() {
    final f = fail;
    fail = null;
    if (f != null) Error.throwWithStackTrace(f, StackTrace.current);
  }

  @override
  Future<String> createPage() async {
    calls.add('create');
    _maybeFail();
    return 'p1';
  }

  @override
  Future<void> navigate(String id, Uri url, Map<String, String> h) async {
    calls.add('navigate $id $url ${jsonEncode(h)}');
    _maybeFail();
  }

  @override
  Future<Object?> evaluate(String id, String expression) async {
    calls.add('evaluate $id $expression');
    _maybeFail();
    return {'v': 1};
  }

  @override
  Future<void> closePage(String id) async => calls.add('close $id');

  @override
  Future<void> open(Uri url) async {
    calls.add('open $url');
    _maybeFail();
  }

  @override
  Future<void> finish(Uri url) async => calls.add('finish $url');

  @override
  Future<String?> cookieHeader(Uri url) async {
    _maybeFail();
    return cookie;
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

List<int> body(Object o) => utf8.encode(jsonEncode(o));

void main() {
  late FakeEngine engine;
  late Harness h;

  setUp(() async {
    engine = FakeEngine();
    h = await Harness.start(engine: engine);
  });
  tearDown(() => h.close());

  test('page lifecycle maps onto the engine', () async {
    final created = await h.call('POST', '/engine/page');
    expect(jsonDecode(text(created)), {'id': 'p1'});
    final nav = await h.call(
      'POST',
      '/engine/page/p1/navigate',
      body: body({
        'url': 'https://site.test/c',
        'headers': {'Referer': 'https://site.test/', 'N': 2},
      }),
    );
    expect(nav.status, 204);
    final ev = await h.call(
      'POST',
      '/engine/page/p1/evaluate',
      body: body({'expression': '1+1'}),
    );
    expect(jsonDecode(text(ev)), {
      'value': {'v': 1},
    });
    expect((await h.call('DELETE', '/engine/page/p1')).status, 204);
    expect(engine.calls, [
      'create',
      'navigate p1 https://site.test/c {"Referer":"https://site.test/","N":"2"}',
      'evaluate p1 1+1',
      'close p1',
    ]);
  });

  test('open and finish take the URL from the body', () async {
    final url = body({'url': 'https://site.test/login'});
    expect((await h.call('POST', '/engine/open', body: url)).status, 202);
    expect((await h.call('POST', '/engine/finish', body: url)).status, 204);
    expect(engine.calls, [
      'open https://site.test/login',
      'finish https://site.test/login',
    ]);
  });

  test('refusals become status + error code', () async {
    Future<String> post(String path, Object b) async {
      final r = await h.call('POST', path, body: body(b));
      return '${r.status} ${text(r)}'.trim();
    }

    engine.fail = const EngineError(409, 'headless-only');
    expect(
      await post('/engine/open', {'url': 'https://a.test/'}),
      '409 {"error":"headless-only"}',
    );
    engine.fail = const CdpException('Page.navigate', 'boom');
    expect(
      await post('/engine/page/p1/navigate', {'url': 'https://a.test/'}),
      '502 {"error":"boom"}',
    );
    expect(
      await post('/engine/page/p1/evaluate', {'expression': 3}),
      '400 {"error":"bad-request"}',
    );
    expect(
      await post('/engine/page/p1/evaluate', [1]),
      '400 {"error":"bad-request"}',
    );
    final huge = await h.call(
      'POST',
      '/engine/open',
      body: List.filled((1 << 20) + 10, 32),
    );
    expect(huge.status, 400);
    expect(await post('/engine/nope', {}), '404');
    expect((await h.call('GET', '/engine/open')).status, 404);
    expect(engine.calls, [
      'open https://a.test/',
      'navigate p1 https://a.test/ {}',
    ]);
  });

  test('only non-loopback http(s) and data: URLs are accepted', () async {
    for (final bad in [
      'http://127.0.0.1:47391/',
      'http://localhost:${h.server.port}/',
      'http://[::1]/',
      'http://0.0.0.0/',
      'http://x.localhost/',
      'file:///etc/passwd',
      'https:///nohost',
      ':',
    ]) {
      final r = await h.call('POST', '/engine/open', body: body({'url': bad}));
      expect(r.status, 400, reason: bad);
    }
    final data = await h.call(
      'POST',
      '/engine/open',
      body: body({'url': 'data:text/html,<p>x</p>'}),
    );
    expect(data.status, 202);
    expect(engineUrlAllowed(Uri.parse('http://127.0.0.1:9/'), 5), isFalse);
    expect(
      engineUrlAllowed(
        Uri.parse('http://127.0.0.1:9/'),
        5,
        allowLoopback: true,
      ),
      isTrue,
    );
    expect(
      engineUrlAllowed(
        Uri.parse('http://127.0.0.1:5/'),
        5,
        allowLoopback: true,
      ),
      isFalse,
    );
  });

  test('the engine is an API: x-kartka and same-origin writes only', () async {
    expect((await h.call('POST', '/engine/page', api: false)).status, 403);
    final cross = await h.call(
      'POST',
      '/engine/page',
      headers: {'origin': 'https://evil.test'},
    );
    expect(cross.status, 403);
    expect(engine.calls, isEmpty);
  });

  test('stopping the wrapper stops the engine', () async {
    await h.server.stop();
    expect(engine.calls, contains('stop'));
  });
}
