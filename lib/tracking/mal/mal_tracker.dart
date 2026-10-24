/// MyAnimeList as a [Tracker] (contracts §9).
library;

import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mal/mal_api.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// List status to send with a progress update, or `null` to leave it.
///
/// Not on the list or `plan_to_read` becomes `reading`; reaching a known
/// [total] becomes `completed`. `on_hold`/`dropped` stay as the user set
/// them unless the series is finished.
String? malNextStatus({
  required String? current,
  required int chaptersRead,
  required int? total,
}) {
  if (total != null && chaptersRead >= total) {
    return current == 'completed' ? null : 'completed';
  }
  if (current == null || current == 'plan_to_read') return 'reading';
  return null;
}

/// MyAnimeList tracker. Remote ids are MAL manga ids as strings.
class MalTracker implements Tracker {
  /// Creates the tracker.
  new({required this._auth, required this._store, required this._api});

  final MalAuth _auth;
  final MalTokenStore _store;
  final MalApi _api;

  @override
  String get id => 'mal';

  @override
  String get name => 'MyAnimeList';

  @override
  Future<bool> isLoggedIn() async => await _store.read() != null;

  @override
  Future<void> login() => _auth.login();

  /// MAL has no token revocation endpoint; forgetting the tokens is all
  /// logout can do.
  @override
  Future<void> logout() => _store.clear();

  @override
  Future<List<TrackSearchResult>> search(String title) async => [
    for (final m in await _api.search(title))
      TrackSearchResult(
        remoteId: '${m.id}',
        title: m.title,
        coverUrl: m.coverUrl,
        chapters: m.totalChapters,
      ),
  ];

  @override
  Future<TrackStatus?> fetch(String remoteId) async {
    final manga = await _api.manga(_parseId(remoteId));
    final entry = manga?.listStatus;
    if (manga == null || entry == null) return null;
    return TrackStatus(
      remoteId: remoteId,
      chaptersRead: entry.chaptersRead,
      totalChapters: manga.totalChapters,
      status: entry.status,
      score: entry.score?.toDouble(),
    );
  }

  /// Reads the remote entry first and PATCHes only when [chaptersRead]
  /// (capped at the known total) is above the remote count, so a stale
  /// device can never lower progress on MAL.
  @override
  Future<void> pushProgress(String remoteId, int chaptersRead) async {
    final id = _parseId(remoteId);
    final manga = await _api.manga(id);
    if (manga == null) {
      throw const MalException('unknown MAL id', statusCode: 404);
    }
    final total = manga.totalChapters;
    final entry = manga.listStatus;
    final target = total != null && chaptersRead > total ? total : chaptersRead;
    if (target <= (entry?.chaptersRead ?? 0)) return;
    await _api.updateListStatus(
      id,
      chaptersRead: target,
      status: malNextStatus(
        current: entry?.status,
        chaptersRead: target,
        total: total,
      ),
    );
  }

  static int _parseId(String remoteId) {
    final id = int.tryParse(remoteId);
    if (id == null) {
      throw ArgumentError.value(remoteId, 'remoteId', 'not a MAL id');
    }
    return id;
  }
}
