/// MyAnimeList OAuth tokens and their storage.
library;

import 'dart:convert';

/// Access + refresh token pair. MAL rotates both on every refresh.
class MalTokens {
  /// Creates a token pair.
  const new({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Builds tokens from a `/v1/oauth2/token` response received at [now].
  ///
  /// Uses `expires_in` instead of a hard-coded lifetime (MAL has changed
  /// it before: documented as 1 h, observed as 31 days).
  factory fromTokenResponse(Map<String, Object?> json, DateTime now) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiresIn = json['expires_in'];
    if (access is! String || refresh is! String || expiresIn is! int) {
      throw const FormatException('incomplete MAL token response');
    }
    return MalTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: now.toUtc().add(Duration(seconds: expiresIn)),
    );
  }

  /// Restores tokens written by [toJson].
  factory fromJson(Map<String, Object?> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expires = json['expiresAt'];
    if (access is! String || refresh is! String || expires is! String) {
      throw const FormatException('malformed stored MAL tokens');
    }
    return MalTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.parse(expires),
    );
  }

  /// Bearer token for API calls.
  final String accessToken;

  /// Token used to get a new pair.
  final String refreshToken;

  /// When [accessToken] stops working (UTC).
  final DateTime expiresAt;

  /// Whether the access token is expired or within 5 minutes of it.
  bool isExpired(DateTime now) =>
      !now.isBefore(expiresAt.subtract(const Duration(minutes: 5)));

  /// Same tokens with a different [expiresAt].
  MalTokens copyWithExpiry(DateTime expiresAt) => MalTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
  );

  /// JSON for [MalTokenStore] implementations.
  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is MalTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt.isAtSameMomentAs(expiresAt);

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, expiresAt.millisecondsSinceEpoch);

  @override
  String toString() => 'MalTokens(expiresAt: $expiresAt)';
}

/// Persists [MalTokens] on this device (never synced).
abstract interface class MalTokenStore {
  /// Stored tokens, or `null` when logged out.
  Future<MalTokens?> read();

  /// Replaces the stored tokens.
  Future<void> write(MalTokens tokens);

  /// Forgets the stored tokens.
  Future<void> clear();
}

/// [MalTokenStore] over any string key-value store (e.g. `KeyValueStore`).
class StringMalTokenStore implements MalTokenStore {
  /// Creates a store using the given key-value callbacks.
  new({
    required this._read,
    required this._write,
    required this._delete,
    this.key = defaultKey,
  });

  /// Key used unless another is given.
  static const defaultKey = 'tracking.mal.tokens';

  /// Key the tokens are stored under.
  final String key;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  @override
  Future<MalTokens?> read() async {
    final raw = await _read(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, Object?> ? MalTokens.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(MalTokens tokens) =>
      _write(key, jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _delete(key);
}
