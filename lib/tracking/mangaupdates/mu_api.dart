/// MangaUpdates API v1 endpoints Kartka uses.
library;

import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/tracking/mangaupdates/mu_client.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

/// Login, series search and reading-list access.
class MuApi {
  /// Creates the API on [_client], keeping the session in [_store].
  new({required this._client, required this._store});

  final MuClient _client;
  final MuSessionStore _store;

  /// `PUT /account/login`: trades credentials for a session token and
  /// stores it. Throws [MuAuthException] with the server's reason.
  Future<MuSession> login(String username, String password) async {
    final res = await _client.send(
      'PUT',
      '/account/login',
      json: {'username': username, 'password': password},
    );
    final json = _tryDecode(res.body);
    final context = json is Map<String, Object?> ? json['context'] : null;
    final token = context is Map<String, Object?>
        ? context['session_token']
        : null;
    if (!res.ok || token is! String || token.isEmpty) {
      throw MuAuthException(
        _reason(json) ?? 'MangaUpdates login failed',
        statusCode: res.statusCode,
      );
    }
    final session = MuSession(token: token, username: username);
    await _store.write(session);
    return session;
  }

  /// `POST /account/logout`, then forgets the token whatever the server
  /// said: a dead session must not keep the app "logged in".
  Future<void> logout() async {
    final session = await _store.read();
    if (session == null) return;
    try {
      await _client.send('POST', '/account/logout', token: session.token);
    } on Exception {
      // Offline or already expired: forgetting locally is what matters.
    } finally {
      await _store.clear();
    }
  }

  /// `POST /series/search`, first page, without novels and drama CDs.
  Future<List<MuSeries>> search(String title) async {
    final q = title.trim();
    if (q.isEmpty) return const [];
    final res = await _client.send(
      'POST',
      '/series/search',
      json: {'search': q, 'perpage': 10},
    );
    final json = _decode(_checked(res));
    final results = json is Map<String, Object?> ? json['results'] : null;
    if (results is! List<Object?>) {
      throw const MuException('malformed search response');
    }
    return [
      for (final r in results)
        if (r is Map<String, Object?> && r['record'] is Map<String, Object?>)
          _parse(() => MuSeries.fromJson(r['record']! as Map<String, Object?>)),
    ].where((s) => !muHiddenTypes.contains(s.type)).toList();
  }

  /// `GET /lists/series/{id}`: the user's entry, `null` when not listed.
  Future<MuListItem?> listItem(int seriesId) async {
    final res = await _authed('GET', '/lists/series/$seriesId');
    if (res.statusCode == 404) return null;
    final json = _decode(_checked(res));
    if (json is! Map<String, Object?>) {
      throw const MuException('malformed list entry');
    }
    if (json.isEmpty) {
      // The API answers a dead token here with 200 `{}`, not 401 (seen
      // live). Only a working session makes `{}` mean "not listed".
      _checked(await _authed('GET', '/account/profile'));
      return null;
    }
    return _parse<MuListItem>(() => MuListItem.fromJson(json));
  }

  /// `POST /lists/series`: puts the series on [listId] at [chapter].
  Future<void> addToList(
    int seriesId, {
    required int chapter,
    int listId = muReadingList,
  }) => _write('/lists/series', seriesId, listId, chapter);

  /// `POST /lists/series/update`: sets [chapter], staying on [listId].
  Future<void> updateChapter(
    int seriesId, {
    required int listId,
    required int chapter,
  }) => _write('/lists/series/update', seriesId, listId, chapter);

  Future<void> _write(String path, int id, int listId, int chapter) async {
    _checked(
      await _authed(
        'POST',
        path,
        write: true,
        json: [
          {
            'series': {'id': id},
            'list_id': listId,
            'status': {'chapter': chapter},
          },
        ],
      ),
    );
  }

  Future<KartkaResponse> _authed(
    String method,
    String path, {
    Object? json,
    bool write = false,
  }) async {
    final session = await _store.read();
    if (session == null) {
      throw const MuAuthException('not logged in to MangaUpdates');
    }
    final res = await _client.send(
      method,
      path,
      json: json,
      token: session.token,
      write: write,
    );
    if (res.statusCode != 401) return res;
    // Session tokens cannot be refreshed: the user logs in again.
    await _store.clear();
    throw MuAuthException(
      _reason(_tryDecode(res.body)) ?? 'MangaUpdates session expired',
      statusCode: 401,
    );
  }

  static KartkaResponse _checked(KartkaResponse res) {
    if (res.ok) return res;
    throw MuException(
      _reason(_tryDecode(res.body)) ?? 'MangaUpdates request failed',
      statusCode: res.statusCode,
    );
  }

  static Object? _decode(KartkaResponse res) {
    final json = _tryDecode(res.body);
    if (json == null) throw const MuException('expected JSON');
    return json;
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String? _reason(Object? json) {
    final reason = json is Map<String, Object?> ? json['reason'] : null;
    return reason is String && reason.isNotEmpty ? reason : null;
  }

  static T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw MuException(e.message);
    }
  }
}
