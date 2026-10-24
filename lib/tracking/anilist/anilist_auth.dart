import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/oauth_redirect.dart';
import 'package:kartka/tracking/anilist/anilist_queries.dart';

/// AniList client ids, one per redirect URI.
///
/// AniList's implicit grant always redirects to the client's single
/// registered URL, so Android and web each need their own client
/// (contracts §13). The ids come from `--dart-define-from-file`
/// (`~/.config/kartka/oauth.json`), never from the repo.
class AniListClientIds {
  /// Creates explicit ids (tests, overrides).
  const new({required this.android, required this.web});

  /// Reads the build-time dart-defines.
  const new fromEnvironment()
    : android = const String.fromEnvironment(
        'KARTKA_ANILIST_CLIENT_ID_ANDROID',
      ),
      web = const String.fromEnvironment('KARTKA_ANILIST_CLIENT_ID_WEB');

  /// Client registered for `kartka://oauth`.
  final String android;

  /// Client registered for `http://127.0.0.1:8791/oauth`.
  final String web;

  /// The id registered for [redirect], or `null` when not configured.
  String? forRedirect(Uri redirect) {
    final id = redirect.scheme == 'kartka' ? android : web;
    return id.isEmpty ? null : id;
  }
}

/// The provider refused or broke the sign-in.
class AniListAuthError implements Exception {
  /// Creates the error with the provider's [reason].
  const new(this.reason);

  /// `error` from the redirect, or a description of what was missing.
  final String reason;

  @override
  String toString() => 'AniListAuthError: $reason';
}

/// Implicit-grant sign-in and token storage in `KartkaPlatform.secrets`.
class AniListAuth {
  /// Creates the auth helper.
  new({
    required this._secrets,
    required this._oauth,
    required AniListClientIds clientIds,
    DateTime Function()? now,
  }) : _ids = clientIds,
       _now = now ?? DateTime.now;

  /// Secrets key holding `{token, expiresAt}`.
  static const tokenKey = 'tracking.anilist.token';

  final KeyValueStore _secrets;
  final OAuthRedirect _oauth;
  final AniListClientIds _ids;
  final DateTime Function() _now;

  /// The stored access token, or `null` when absent, corrupt or expired.
  Future<String?> token() async {
    final raw = await _secrets.get(tokenKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final expires = json['expiresAt'] as String?;
      if (expires != null && !_now().isBefore(DateTime.parse(expires))) {
        return null;
      }
      return json['token']! as String;
    } on Object {
      return null;
    }
  }

  /// Runs the browser round trip and stores the granted token.
  Future<void> login() async {
    final clientId = _ids.forRedirect(_oauth.redirectUri);
    if (clientId == null) {
      throw StateError(
        'AniList client id missing: run tools/tracking/register_anilist.sh '
        'and build with --dart-define-from-file',
      );
    }
    final redirect = await _oauth.authorize(
      aniListAuthorize.replace(
        queryParameters: {'client_id': clientId, 'response_type': 'token'},
      ),
    );
    final params = {
      ...redirect.queryParameters,
      if (redirect.fragment.isNotEmpty)
        ...Uri.splitQueryString(redirect.fragment),
    };
    final error = params['error'];
    if (error != null) throw AniListAuthError(error);
    final token = params['access_token'];
    if (token == null || token.isEmpty) {
      throw const AniListAuthError('no access_token in the redirect');
    }
    final seconds = int.tryParse(params['expires_in'] ?? '');
    await _secrets.set(
      tokenKey,
      jsonEncode({
        'token': token,
        if (seconds != null)
          'expiresAt': _now()
              .toUtc()
              .add(Duration(seconds: seconds))
              .toIso8601String(),
      }),
    );
  }

  /// Forgets the token.
  Future<void> logout() => _secrets.remove(tokenKey);
}
