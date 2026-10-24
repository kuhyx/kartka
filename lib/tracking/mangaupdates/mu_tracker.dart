/// MangaUpdates as a [Tracker] (contracts §9).
library;

import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mangaupdates/mu_api.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

/// Username and password typed into the login sheet.
typedef MuCredentials = ({String username, String password});

/// Asks the user for credentials; `null` when they cancel.
typedef MuCredentialsPrompt = Future<MuCredentials?> Function();

/// MangaUpdates tracker. Remote ids are API v1 series ids as decimal
/// strings, the same value a Mihon/SY `.tachibk` stores as `mediaId`.
class MangaUpdatesTracker implements Tracker {
  /// Creates the tracker. `prompt` makes [login] work without a
  /// `BuildContext`; without it, UIs call [loginWith] from the login sheet.
  new({required this._api, required this._store, this._prompt});

  final MuApi _api;
  final MuSessionStore _store;
  final MuCredentialsPrompt? _prompt;

  @override
  String get id => 'mangaupdates';

  @override
  String get name => 'MangaUpdates';

  @override
  Future<bool> isLoggedIn() async => await _store.read() != null;

  /// Who is logged in, or `null`.
  Future<String?> username() async => (await _store.read())?.username;

  /// MangaUpdates has no OAuth: asks the prompt for a username and
  /// password, then logs in. A cancelled prompt does nothing.
  @override
  Future<void> login() async {
    final prompt = _prompt;
    if (prompt == null) {
      throw const MuAuthException(
        'MangaUpdates logs in with a username and password: '
        'use the MangaUpdates login sheet',
      );
    }
    final c = await prompt();
    if (c != null) await loginWith(c.username, c.password);
  }

  /// Logs in with [username] and [password]; only the session token is kept.
  Future<void> loginWith(String username, String password) =>
      _api.login(username, password);

  @override
  Future<void> logout() => _api.logout();

  /// `chapters` stays null: MangaUpdates only knows the latest release,
  /// which is not a total.
  @override
  Future<List<TrackSearchResult>> search(String title) async => [
    for (final s in await _api.search(title))
      TrackSearchResult(
        remoteId: '${s.id}',
        title: s.title,
        coverUrl: s.coverUrl,
      ),
  ];

  @override
  Future<TrackStatus?> fetch(String remoteId) async {
    final item = await _api.listItem(_parseId(remoteId));
    if (item == null) return null;
    return TrackStatus(
      remoteId: remoteId,
      chaptersRead: item.chapter,
      status: item.status,
    );
  }

  /// Reads the entry first and writes only when [chaptersRead] is above the
  /// remote count, so a stale device never lowers progress. A series that is
  /// not listed yet goes on the Reading List; one on another list (complete,
  /// on hold, custom) stays there.
  @override
  Future<void> pushProgress(String remoteId, int chaptersRead) async {
    final id = _parseId(remoteId);
    final item = await _api.listItem(id);
    if (chaptersRead <= (item?.chapter ?? 0)) return;
    if (item == null) {
      await _api.addToList(id, chapter: chaptersRead);
    } else {
      await _api.updateChapter(id, listId: item.listId, chapter: chaptersRead);
    }
  }

  static int _parseId(String remoteId) {
    final id = int.tryParse(remoteId);
    if (id == null) {
      throw ArgumentError.value(remoteId, 'remoteId', 'not a series id');
    }
    return id;
  }
}
