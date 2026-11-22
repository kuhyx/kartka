import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// Chapter 2.5, released after the stored list was saved.
const chapter25 = ChapterInfo(url: '/c/2.5', name: 'Ch. 2.5', number: 2.5);

/// The fresh list once chapter 2.5 is out.
const List<ChapterInfo> freshChapters = [
  ChapterInfo(url: '/c/3', name: 'Ch. 3', number: 3),
  chapter25,
  ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2),
  ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
];

/// A source whose chapter list waits on [list] (Suwayomi fetching it from
/// the site) and whose page lists wait on [pageGates].
class GatedSource extends FakeSource {
  new({super.pageMap, this.list, super.chapterList = sessionChapters});

  /// When set, the chapter list is what this completes with.
  final Completer<List<ChapterInfo>>? list;

  /// Page lists that wait for their completer.
  final Map<String, Completer<void>> pageGates = {};

  /// Page lists asked for, in order, when asked (not when answered).
  final List<String> asked = [];

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) =>
      list?.future ?? super.chapters(mangaUrl);

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    asked.add(chapterUrl);
    await pageGates[chapterUrl]?.future;
    return await super.pages(chapterUrl);
  }
}

/// Browse's stored chapter lists: [list] for every manga.
class StoredLists implements StoredChapterLists {
  const new(this.list, {this.error});

  /// What every [stored] call answers.
  final List<ChapterInfo>? list;

  /// When set, every [stored] call throws it.
  final Error? error;

  @override
  Future<List<ChapterInfo>?> stored(MangaKey key) async {
    if (error case final e?) throw e;
    return list;
  }
}
