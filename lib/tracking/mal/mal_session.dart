/// Authorized MAL calls with transparent token refresh.
library;

import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// Builds a request given the auth headers to attach.
typedef MalRequestBuilder = MalRequest Function(Map<String, String> auth);

/// Sends requests with the stored bearer token, refreshing it when it is
/// expired or MAL answers 401 (reusing a pair another call already
/// rotated). Refreshes at most once per call; a second
/// 401 logs out. Other statuses (403 = MAL's DoS guard) are returned
/// untouched and never retried.
class MalSession {
  /// Creates a session.
  new({
    required this._auth,
    required this._store,
    required this._send,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MalAuth _auth;
  final MalTokenStore _store;
  final MalSend _send;
  final DateTime Function() _now;

  /// Sends the request [build] produces with a valid bearer token.
  Future<MalResponse> authorized(MalRequestBuilder build) async {
    var tokens = await _store.read();
    if (tokens == null) throw const MalAuthException('not logged in to MAL');
    if (tokens.isExpired(_now())) tokens = await _auth.refresh(tokens);
    var res = await _send(build(_bearer(tokens)));
    if (res.statusCode != 401) return res;
    // Another call may have rotated the pair while this one was in flight.
    final stored = await _store.read();
    tokens = stored != null && stored.accessToken != tokens.accessToken
        ? stored
        : await _auth.refresh(tokens);
    res = await _send(build(_bearer(tokens)));
    if (res.statusCode != 401) return res;
    await _store.clear();
    throw const MalAuthException('MAL rejected a fresh token', statusCode: 401);
  }

  static Map<String, String> _bearer(MalTokens t) => {
    'Authorization': 'Bearer ${t.accessToken}',
  };
}
