// Shared fakes for the MAL tests.
//
// The fixtures under test/fixtures/tracking-mal/ were built from the
// documented MAL API v2 shapes (myanimelist.net/apiconfig/references/api/v2
// and the MAL OAuth guide, blog eid=835707), not recorded live, because no
// client id existed when they were written. The `live`-tagged smoke test in
// mal_live_test.dart checks them against the real API.
import 'dart:io';

import 'package:kartka/tracking/mal/mal_api.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_session.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// Reads a fixture body from test/fixtures/tracking-mal/.
String fixture(String name) =>
    File('test/fixtures/tracking-mal/$name').readAsStringSync();

/// Decides the response for one request.
typedef FakeHandler = MalResponse Function(MalRequest request);

/// Transport that records every request and answers from [handler].
class FakeTransport {
  /// Creates a transport answering with [handler].
  new(this.handler);

  /// Answers each request in turn from [responses].
  new queue(List<MalResponse> responses) : handler = _fromQueue(responses);

  /// Current response policy, replaceable mid-test.
  FakeHandler handler;

  /// Every request seen, oldest first.
  final List<MalRequest> requests = [];

  /// The [MalSend] to hand to the code under test.
  Future<MalResponse> send(MalRequest request) async {
    requests.add(request);
    return handler(request);
  }

  /// Requests made with [method].
  List<MalRequest> withMethod(MalMethod method) =>
      requests.where((r) => r.method == method).toList();

  static FakeHandler _fromQueue(List<MalResponse> responses) {
    final pending = [...responses];
    return (_) => pending.removeAt(0);
  }
}

/// In-memory [MalTokenStore].
class MemoryTokenStore implements MalTokenStore {
  /// Creates a store holding [tokens].
  new([this.tokens]);

  /// Currently stored tokens.
  MalTokens? tokens;

  @override
  Future<MalTokens?> read() async => tokens;

  @override
  Future<void> write(MalTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

/// Fixed clock used by every test.
final DateTime testNow = DateTime.utc(2026, 10, 24, 12);

/// Tokens that are valid at [testNow].
MalTokens validTokens({String access = 'access-0'}) => MalTokens(
  accessToken: access,
  refreshToken: 'refresh-0',
  expiresAt: testNow.add(const Duration(days: 10)),
);

/// Response with [status] and the fixture [name] as body.
MalResponse fx(int status, String name) => MalResponse(status, fixture(name));

/// Builds a [MalApi] over [http] with a logged-in store.
MalApi buildApi(FakeTransport http, [MemoryTokenStore? store]) {
  final tokens = store ?? MemoryTokenStore(validTokens());
  return MalApi(
    clientId: 'cid',
    send: http.send,
    session: MalSession(
      auth: MalAuth(
        client: const MalOAuthClient(clientId: 'cid', redirectUri: 'x://y'),
        send: http.send,
        store: tokens,
        launch: (_) => throw UnimplementedError(),
        now: () => testNow,
      ),
      store: tokens,
      send: http.send,
      now: () => testNow,
    ),
  );
}
