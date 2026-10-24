import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/tracker.dart';

/// In-memory remote list: `remoteId -> chaptersRead`.
class FakeTracker implements Tracker {
  new({this.id = 'anilist', this.loggedIn = true});

  @override
  final String id;
  bool loggedIn;
  final Map<String, int> remote = {};
  final List<(String, int)> pushes = [];
  int fetches = 0;
  Exception? pushError;
  Exception? loginError;
  Exception? searchError;
  bool emptySearch = false;
  Completer<void>? gate;

  @override
  String get name => id.toUpperCase();

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> login() async {
    final e = loginError;
    if (e != null) throw e;
    loggedIn = true;
  }

  @override
  Future<void> logout() async => loggedIn = false;

  @override
  Future<List<TrackSearchResult>> search(String title) async {
    final e = searchError;
    if (e != null) throw e;
    if (emptySearch) return const [];
    return [TrackSearchResult(remoteId: '1', title: title, chapters: 4)];
  }

  @override
  Future<TrackStatus?> fetch(String remoteId) async {
    fetches++;
    final read = remote[remoteId];
    return read == null
        ? null
        : TrackStatus(
            remoteId: remoteId,
            chaptersRead: read,
            status: 'CURRENT',
          );
  }

  @override
  Future<void> pushProgress(String remoteId, int chaptersRead) async {
    await gate?.future;
    final e = pushError;
    if (e != null) throw e;
    pushes.add((remoteId, chaptersRead));
    final now = remote[remoteId] ?? 0;
    if (chaptersRead > now) remote[remoteId] = chaptersRead;
  }
}

/// Resolves chapter N to `/chapter/N`, or nothing when [known] is false.
class FakeResolver implements ChapterUrlResolver {
  bool known = true;

  @override
  Future<String?> resolve(MangaKey key, int chapterNumber) async =>
      known ? '/chapter/$chapterNumber' : null;
}

/// Progress at [chapter] for [key].
ReadingProgress progressAt(MangaKey key, double chapter, {int page = 0}) =>
    ReadingProgress(
      key: key,
      chapterUrl: '/chapter/$chapter',
      chapterNumber: chapter,
      page: page,
      readAt: DateTime.utc(2026),
    );
