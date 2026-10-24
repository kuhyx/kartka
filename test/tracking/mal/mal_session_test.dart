import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_session.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

void main() {
  late FakeTransport http;
  late MemoryTokenStore store;
  late MalSession session;
  final api = Uri.parse('https://api.myanimelist.net/v2/manga/2');

  MalRequest get(Map<String, String> auth) =>
      MalRequest(MalMethod.get, api, headers: auth);

  setUp(() {
    http = FakeTransport((_) => const MalResponse(200, '{}'));
    store = MemoryTokenStore(validTokens());
    session = MalSession(
      auth: MalAuth(
        client: const MalOAuthClient(clientId: 'cid', redirectUri: 'x://y'),
        send: http.send,
        store: store,
        launch: (_) => throw UnimplementedError(),
        random: Random(1),
        now: () => testNow,
      ),
      store: store,
      send: http.send,
      now: () => testNow,
    );
  });

  test('sends the bearer token', () async {
    final res = await session.authorized(get);
    expect(res.statusCode, 200);
    expect(http.requests.single.headers, {'Authorization': 'Bearer access-0'});
  });

  test('not logged in throws without any request', () async {
    store.tokens = null;
    await expectLater(
      session.authorized(get),
      throwsA(isA<MalAuthException>()),
    );
    expect(http.requests, isEmpty);
  });

  test('expired token is refreshed before the call', () async {
    store.tokens = validTokens().copyWithExpiry(testNow);
    http.handler = (r) => r.url.path.endsWith('token')
        ? fx(200, 'token_refreshed.json')
        : const MalResponse(200, '{}');
    await session.authorized(get);
    expect(http.requests, hasLength(2));
    expect(http.requests.last.headers['Authorization'], 'Bearer access-2');
  });

  test('401 refreshes once and retries', () async {
    http = FakeTransport.queue([
      fx(401, 'invalid_token.json'),
      fx(200, 'token_refreshed.json'),
      const MalResponse(200, '{"ok":1}'),
    ]);
    session = _rebuild(http, store);
    final res = await session.authorized(get);
    expect(res.body, '{"ok":1}');
    expect(http.requests.last.headers['Authorization'], 'Bearer access-2');
    expect(store.tokens!.refreshToken, 'refresh-2');
  });

  test('401 after a refresh logs out', () async {
    http = FakeTransport.queue([
      fx(401, 'invalid_token.json'),
      fx(200, 'token_refreshed.json'),
      fx(401, 'invalid_token.json'),
    ]);
    session = _rebuild(http, store);
    await expectLater(
      session.authorized(get),
      throwsA(isA<MalAuthException>()),
    );
    expect(store.tokens, isNull);
  });

  test('403 (DoS guard) is returned as-is, never retried', () async {
    http.handler = (_) => const MalResponse(403, '');
    final res = await session.authorized(get);
    expect(res.statusCode, 403);
    expect(http.requests, hasLength(1));
  });
}

MalSession _rebuild(FakeTransport http, MemoryTokenStore store) => MalSession(
  auth: MalAuth(
    client: const MalOAuthClient(clientId: 'cid', redirectUri: 'x://y'),
    send: http.send,
    store: store,
    launch: (_) => throw UnimplementedError(),
    now: () => testNow,
  ),
  store: store,
  send: http.send,
  now: () => testNow,
);
