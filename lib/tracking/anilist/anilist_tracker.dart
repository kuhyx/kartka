import 'package:kartka/tracking/anilist/anilist_api.dart';
import 'package:kartka/tracking/anilist/anilist_auth.dart';
import 'package:kartka/tracking/anilist/anilist_parse.dart';
import 'package:kartka/tracking/anilist/anilist_queries.dart';
import 'package:kartka/tracking/anilist/anilist_status.dart';
import 'package:kartka/tracking/common/tracker.dart';

/// AniList [Tracker] (contracts §9) over GraphQL.
class AniListTracker implements Tracker {
  /// Creates the tracker.
  new({required this._api, required this._auth});

  final AniListApi _api;
  final AniListAuth _auth;

  @override
  String get id => 'anilist';

  @override
  String get name => 'AniList';

  @override
  Future<bool> isLoggedIn() async => await _auth.token() != null;

  @override
  Future<void> login() => _auth.login();

  @override
  Future<void> logout() => _auth.logout();

  @override
  Future<List<TrackSearchResult>> search(String title) async => parseSearch(
    await _call(searchQuery, {'search': title}, await _auth.token()),
  );

  @override
  Future<TrackStatus?> fetch(String remoteId) async => parseFetch(
    await _call(fetchQuery, {'id': int.parse(remoteId)}, await _token()),
  );

  @override
  Future<void> pushProgress(String remoteId, int chaptersRead) async {
    final token = await _token();
    if (chaptersRead <= 0) return;
    final current = await fetch(remoteId);
    if (current != null && current.chaptersRead >= chaptersRead) return;
    final status = statusAfterPush(current: current, progress: chaptersRead);
    parseSaved(
      await _call(saveMutation, {
        'mediaId': int.parse(remoteId),
        'progress': chaptersRead,
        'status': ?status,
      }, token),
    );
  }

  Future<String> _token() async {
    final token = await _auth.token();
    if (token == null) throw StateError('not logged in to AniList');
    return token;
  }

  /// Runs a request and parses errors; an auth error drops the dead token.
  Future<Map<String, Object?>> _call(
    String query,
    Map<String, Object?> variables,
    String? token,
  ) async {
    final body = await _api.call(query, variables, token: token);
    try {
      parseErrors(body);
    } on AniListException catch (e) {
      if (e.isAuthError) await _auth.logout();
      rethrow;
    }
    return body;
  }
}
