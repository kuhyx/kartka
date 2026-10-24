/// MyAnimeList OAuth2 authorization-code flow with plain PKCE.
library;

import 'dart:convert';
import 'dart:math';

import 'package:kartka/tracking/mal/mal_pkce.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// Authorization endpoint.
const malAuthorizeEndpoint = 'https://myanimelist.net/v1/oauth2/authorize';

/// Token endpoint (code exchange and refresh).
const malTokenEndpoint = 'https://myanimelist.net/v1/oauth2/token';

/// A registered MAL app. Public client ("other"/"android" app type), so
/// there is no client secret.
class MalOAuthClient {
  /// Creates a client description.
  const new({required this.clientId, required this.redirectUri});

  /// Client id from the MAL app page.
  final String clientId;

  /// The app's registered redirect URL. MAL matches it exactly, and it is
  /// sent in both the authorize and the token request.
  final String redirectUri;
}

/// Opens [authorizeUrl] in a browser and completes with the redirect URL
/// MAL sent back (`OAuthRedirect`, contracts §7).
typedef MalOAuthLaunch = Future<Uri> Function(Uri authorizeUrl);

/// Runs login and token refresh, persisting tokens in a [MalTokenStore].
class MalAuth {
  /// Creates the flow. [random] and [now] are injectable for tests.
  new({
    required this.client,
    required this._send,
    required this._store,
    required this._launch,
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  /// The registered app.
  final MalOAuthClient client;

  final MalSend _send;
  final MalTokenStore _store;
  final MalOAuthLaunch _launch;
  final Random _random;
  final DateTime Function() _now;

  /// The authorize URL for [verifier] and [state].
  Uri authorizeUrl(String verifier, String state) =>
      Uri.parse(malAuthorizeEndpoint).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': client.clientId,
          'code_challenge': malCodeChallenge(verifier),
          'code_challenge_method': malCodeChallengeMethod,
          'state': state,
          'redirect_uri': client.redirectUri,
        },
      );

  /// Full login: browser consent, state check, code exchange, store.
  Future<MalTokens> login() async {
    final verifier = malCodeVerifier(_random);
    final state = malState(_random);
    final callback = await _launch(authorizeUrl(verifier, state));
    final params = callback.queryParameters;
    if (params['state'] != state) {
      throw const MalAuthException('OAuth state mismatch');
    }
    final error = params['error'];
    if (error != null) throw MalAuthException('MAL login failed: $error');
    final code = params['code'];
    if (code == null) throw const MalAuthException('no code in callback');
    final tokens = await _tokenRequest({
      'client_id': client.clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': client.redirectUri,
    });
    await _store.write(tokens);
    return tokens;
  }

  /// Exchanges [old]'s refresh token for a new pair and stores it.
  ///
  /// MAL rotates the pair on every refresh, so concurrent callers share one
  /// in-flight request, and a caller holding a pair someone else already
  /// rotated gets the stored pair instead of burning a dead refresh token.
  /// Only a credential rejection (400/401) clears the store, and only while
  /// it still holds [old]; transient failures keep the tokens.
  Future<MalTokens> refresh(MalTokens old) =>
      _refreshing ??= _refresh(old).whenComplete(() => _refreshing = null);

  Future<MalTokens>? _refreshing;

  Future<MalTokens> _refresh(MalTokens old) async {
    final stored = await _store.read();
    if (stored != null &&
        stored.refreshToken != old.refreshToken &&
        !stored.isExpired(_now())) {
      return stored;
    }
    try {
      final tokens = await _tokenRequest({
        'client_id': client.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': old.refreshToken,
      });
      await _store.write(tokens);
      return tokens;
    } on MalAuthException {
      final current = await _store.read();
      if (current?.refreshToken == old.refreshToken) await _store.clear();
      rethrow;
    }
  }

  Future<MalTokens> _tokenRequest(Map<String, String> fields) async {
    final res = await _send(
      MalRequest(
        MalMethod.post,
        Uri.parse(malTokenEndpoint),
        headers: const {'Content-Type': malFormContentType},
        body: malForm(fields),
      ),
    );
    if (res.statusCode == 400 || res.statusCode == 401) {
      throw MalAuthException(
        'token request rejected: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    if (!res.ok) {
      throw MalException('token endpoint failed', statusCode: res.statusCode);
    }
    try {
      final json = jsonDecode(res.body);
      if (json is! Map<String, Object?>) throw const FormatException();
      return MalTokens.fromTokenResponse(json, _now());
    } on FormatException {
      throw const MalException('unreadable token response');
    }
  }
}
