/// The MangaUpdates session token and where it lives.
library;

import 'dart:convert';

import 'package:kartka/platform/platform.dart';

/// A logged-in session. The password is never stored.
class MuSession {
  /// Creates a session.
  const new({required this.token, required this.username});

  /// Bearer token from `PUT /v1/account/login`.
  final String token;

  /// Who logged in, for display.
  final String username;
}

/// Keeps the [MuSession] in a [KeyValueStore]. The feature hands it
/// `KartkaPlatform.secrets`, never `kv` (contracts §13).
class MuSessionStore {
  /// Creates a store over [_store].
  new(this._store, {this.key = defaultKey});

  /// Key used unless another is given.
  static const defaultKey = 'tracking.mangaupdates.session';

  final KeyValueStore _store;

  /// Key the session is stored under.
  final String key;

  /// The stored session; `null` when absent or unreadable.
  Future<MuSession?> read() async {
    final raw = await _store.get(key);
    if (raw == null) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final token = json['token'];
    final username = json['username'];
    if (token is! String || username is! String) return null;
    return MuSession(token: token, username: username);
  }

  /// Stores [session].
  Future<void> write(MuSession session) => _store.set(
    key,
    jsonEncode({'token': session.token, 'username': session.username}),
  );

  /// Forgets the session.
  Future<void> clear() => _store.remove(key);
}
