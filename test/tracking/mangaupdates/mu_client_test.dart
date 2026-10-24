import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/mangaupdates/mu_client.dart';

import 'mu_fakes.dart';

void main() {
  late FakeClock clock;
  late List<KartkaResponse> queue;
  late FakeKartkaHttp http;
  late MuClient client;

  setUp(() {
    clock = FakeClock();
    queue = [];
    http = FakeKartkaHttp((_) => queue.removeAt(0));
    client = buildStack(http, clock).client;
  });

  test('sends JSON with bearer token to the v1 base', () async {
    queue.add(fx('list_update_ok.json'));
    final res = await client.send(
      'POST',
      '/lists/series/update',
      json: const [1],
      token: 't',
    );
    expect(res.statusCode, 200);
    final r = http.requests.single;
    expect(r.url.toString(), '$muApiBase/lists/series/update');
    expect(r.headers['Authorization'], 'Bearer t');
    expect(r.headers['Content-Type'], 'application/json');
    expect(r.body, '[1]');
  });

  test('GET without token or body sends neither', () async {
    queue.add(fx('search_empty.json'));
    await client.send('GET', '/x');
    final h = http.requests.single.headers;
    expect(h.containsKey('Authorization'), isFalse);
    expect(h.containsKey('Content-Type'), isFalse);
    expect(http.requests.single.body, isNull);
  });

  test('429 waits Retry-After seconds, then retries', () async {
    queue
      ..add(fx('rate_limited.json', status: 429, headers: {'retry-after': '7'}))
      ..add(fx('search_empty.json'));
    final res = await client.send('POST', '/series/search', json: const {});
    expect(res.statusCode, 200);
    expect(http.requests, hasLength(2));
    expect(clock.sleeps, [const Duration(seconds: 7)]);
  });

  test('429 without Retry-After backs off exponentially, gives up', () async {
    for (var i = 0; i < 4; i++) {
      queue.add(fx('rate_limited.json', status: 429));
    }
    final res = await client.send('GET', '/x');
    expect(res.statusCode, 429);
    expect(http.requests, hasLength(4));
    expect(clock.sleeps, const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
    ]);
  });

  test('412 five-second update delay retries after 5 s', () async {
    queue
      ..add(fx('update_delay.json', status: 412))
      ..add(fx('list_update_ok.json'));
    final res = await client.send('POST', '/lists/series/update', write: true);
    expect(res.statusCode, 200);
    expect(clock.sleeps, [const Duration(seconds: 5)]);
  });

  test('unparseable Retry-After falls back to the default', () async {
    queue
      ..add(fx('rate_limited.json', status: 429, headers: {'retry-after': 'x'}))
      ..add(fx('search_empty.json'));
    await client.send('GET', '/x');
    expect(clock.sleeps, [const Duration(seconds: 5)]);
  });

  test('list writes are spaced at least 5 s apart; reads are not', () async {
    for (var i = 0; i < 4; i++) {
      queue.add(fx('list_update_ok.json'));
    }
    await client.send('GET', '/a');
    await client.send('GET', '/b');
    expect(clock.sleeps, isEmpty);
    await client.send('POST', '/lists/series/update', write: true);
    await client.send('POST', '/lists/series/update', write: true);
    expect(clock.sleeps, [const Duration(seconds: 5)]);
  });

  test('default limiters are polite', () {
    final c = MuClient(http: http);
    expect(c.reads.minGap, const Duration(seconds: 1));
    expect(c.writes.minGap, const Duration(seconds: 5));
  });
}
