import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';

/// A source serving fixed chapters and pages.
class FakeSource implements MangaSource {
  new({
    this.id = 'fake',
    this.chapterList = const [],
    this.pageMap = const {},
    this.failChapters = false,
  });

  final String id;
  final List<ChapterInfo> chapterList;
  final Map<String, List<PageRef>> pageMap;
  final bool failChapters;
  final List<String> pageCalls = [];

  @override
  SourceRef get ref =>
      SourceRef(id: id, name: 'Fake', lang: 'en', origin: SourceOrigin.native);

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    if (failChapters) throw StateError('offline');
    return chapterList;
  }

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    pageCalls.add(chapterUrl);
    final pages = pageMap[chapterUrl];
    if (pages == null) throw StateError('no pages for $chapterUrl');
    return pages;
  }

  @override
  Future<MangaDetails> details(String mangaUrl) => throw UnimplementedError();

  @override
  Future<SearchPage> latest(int page) => throw UnimplementedError();

  @override
  Future<SearchPage> popular(int page) => throw UnimplementedError();

  @override
  Future<SearchPage> search(String query, int page) =>
      throw UnimplementedError();
}

/// Records every progress write.
class FakeProgress implements ProgressRepository {
  new({this.initial});

  final ReadingProgress? initial;
  final List<ReadingProgress> recorded = [];
  final List<String> markedRead = [];

  @override
  Stream<ReadingProgress?> watch(MangaKey key) => Stream.value(initial);

  @override
  Future<void> record(ReadingProgress p) async => recorded.add(p);

  @override
  Future<void> markRead(MangaKey key, String chapterUrl) async =>
      markedRead.add(chapterUrl);

  @override
  Future<void> markUnread(MangaKey key, String chapterUrl) async {}

  @override
  Stream<Set<String>> readChapters(MangaKey key) => Stream.value({});

  @override
  Stream<Map<String, bool>> readMarks(MangaKey key) => Stream.value({});
}

/// Serves offline pages for the chapters in [offline].
class FakeDownloads implements DownloadRepository {
  new([this.offline = const {}]);

  final Map<String, List<PageRef>> offline;

  @override
  Future<void> enqueue(MangaKey key, ChapterInfo chapter) async {}

  @override
  Stream<DownloadState> watch(MangaKey key, String chapterUrl) =>
      const Stream.empty();

  @override
  Future<List<PageRef>?> offlinePages(MangaKey key, String chapterUrl) async =>
      offline[chapterUrl];
}

/// Pages `0..count-1` of [chapter] at fake http URLs.
List<PageRef> fakePages(String chapter, int count) => [
  for (var i = 0; i < count; i++)
    PageRef(
      index: i,
      imageUrl: 'https://img.test$chapter/$i.png',
      headers: const {'Referer': 'https://src.test/'},
    ),
];
