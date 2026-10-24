/// MyAnimeList API v2 manga endpoints Kartka uses.
library;

import 'dart:convert';

import 'package:kartka/tracking/mal/mal_models.dart';
import 'package:kartka/tracking/mal/mal_session.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// API base URL.
const malApiBase = 'https://api.myanimelist.net/v2';

/// Search, entry fetch and list update against MAL API v2.
class MalApi {
  /// Creates the API. `clientId` authenticates public calls
  /// (`X-MAL-CLIENT-ID`); `session` signs user calls.
  new({required this._clientId, required this._send, required this._session});

  final String _clientId;
  final MalSend _send;
  final MalSession _session;

  /// Searches manga by [title]. MAL rejects long queries, so the query is
  /// cut to 64 characters (as Mihon does). Blank titles return nothing.
  Future<List<MalManga>> search(String title) async {
    final q = title.trim();
    if (q.isEmpty) return const [];
    final res = await _send(
      MalRequest(
        MalMethod.get,
        _url('/manga', {
          'q': q.length > 64 ? q.substring(0, 64) : q,
          'limit': '10',
          'fields': 'num_chapters',
          'nsfw': 'true',
        }),
        headers: {'X-MAL-CLIENT-ID': _clientId},
      ),
    );
    final data = _decode(_checked(res))['data'];
    if (data is! List<Object?>) throw const MalException('malformed search');
    return [
      for (final item in data)
        if (item is Map<String, Object?> &&
            item['node'] is Map<String, Object?>)
          _parse(item['node']! as Map<String, Object?>),
    ];
  }

  /// The manga [id] with the user's list entry, or `null` on 404.
  Future<MalManga?> manga(int id) async {
    final res = await _session.authorized(
      (auth) => MalRequest(
        MalMethod.get,
        _url('/manga/$id', {'fields': 'num_chapters,my_list_status'}),
        headers: auth,
      ),
    );
    if (res.statusCode == 404) return null;
    return _parse(_decode(_checked(res)));
  }

  /// Sets `num_chapters_read` (and [status] when given) on manga [id].
  /// Adds the manga to the list if it is not there yet.
  Future<MalListStatus> updateListStatus(
    int id, {
    required int chaptersRead,
    String? status,
  }) async {
    final body = malForm({
      'num_chapters_read': '$chaptersRead',
      'status': ?status,
    });
    final res = await _session.authorized(
      (auth) => MalRequest(
        MalMethod.patch,
        _url('/manga/$id/my_list_status', const {}),
        headers: {...auth, 'Content-Type': malFormContentType},
        body: body,
      ),
    );
    final json = _decode(_checked(res));
    try {
      return MalListStatus.fromJson(json);
    } on FormatException catch (e) {
      throw MalException(e.message);
    }
  }

  static Uri _url(String path, Map<String, String> query) =>
      Uri.parse('$malApiBase$path')
          .replace(queryParameters: query.isEmpty ? null : query);

  static MalResponse _checked(MalResponse res) {
    if (res.ok) return res;
    throw MalException(
      'MAL request failed: ${res.body}',
      statusCode: res.statusCode,
    );
  }

  static Map<String, Object?> _decode(MalResponse res) {
    final json = jsonDecode(res.body);
    if (json is Map<String, Object?>) return json;
    throw const MalException('expected a JSON object from MAL');
  }

  static MalManga _parse(Map<String, Object?> json) {
    try {
      return MalManga.fromJson(json);
    } on FormatException catch (e) {
      throw MalException(e.message);
    }
  }
}
