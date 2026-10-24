import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Manga summary in [source] numbered [i].
MangaSummary manga(String source, int i) =>
    MangaSummary(sourceId: source, url: '/m/$i?x=1#f', title: 'Title $i');

/// Scriptable in-memory source.
class FakeSource implements MangaSource {
  new(
    String id, {
    String? name,
    SourceOrigin origin = SourceOrigin.native,
    this.pageCount = 2,
    this.perPage = 3,
    List<ChapterInfo>? chapters,
  }) : ref = SourceRef(id: id, name: name ?? id, lang: 'en', origin: origin),
       chapterList =
           chapters ??
           [
             for (var n = 3; n >= 1; n--)
               ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
           ];

  @override
  final SourceRef ref;
  final int pageCount;
  final int perPage;
  List<ChapterInfo> chapterList;
  Error? failWith;
  Completer<void>? searchGate;
  final List<String> calls = [];

  SearchPage _page(String kind, int page) {
    calls.add('$kind:$page');
    if (failWith != null) throw failWith!;
    return SearchPage(
      items: [
        for (var i = 0; i < perPage; i++)
          manga(ref.id, (page - 1) * perPage + i),
      ],
      hasNext: page < pageCount,
    );
  }

  @override
  Future<SearchPage> popular(int page) async => _page('popular', page);

  @override
  Future<SearchPage> latest(int page) async => _page('latest', page);

  @override
  Future<SearchPage> search(String query, int page) async {
    await searchGate?.future;
    return _page('search($query)', page);
  }

  @override
  Future<MangaDetails> details(String mangaUrl) async {
    calls.add('details:$mangaUrl');
    if (failWith != null) throw failWith!;
    return MangaDetails(
      sourceId: ref.id,
      url: mangaUrl,
      title: 'Detail title',
      coverUrl: 'https://img.test/cover.jpg',
      authors: const ['Author A'],
      description: 'A long description.',
      genres: const ['Action', 'Drama'],
      status: MangaStatus.ongoing,
    );
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    calls.add('chapters:$mangaUrl');
    if (failWith != null) throw failWith!;
    return chapterList;
  }

  @override
  Future<List<PageRef>> pages(String chapterUrl) async => const [];
}

/// Provider whose list the test pushes.
class FakeSourceProvider implements SourceProvider {
  final controller = StreamController<List<MangaSource>>.broadcast();

  @override
  Stream<List<MangaSource>> watch() => controller.stream;
}

class FakeLibrary implements LibraryRepository {
  final Map<MangaKey, LibraryEntry> entries = {};
  final _c = StreamController<List<LibraryEntry>>.broadcast();

  List<LibraryEntry> get _live => [
    for (final e in entries.values)
      if (!e.removed) e,
  ];

  @override
  Stream<List<LibraryEntry>> watch() async* {
    yield _live;
    yield* _c.stream;
  }

  @override
  Future<void> upsert(LibraryEntry e) async {
    entries[e.key] = e;
    _c.add(_live);
  }

  @override
  Future<void> remove(MangaKey key) async {
    entries.remove(key);
    _c.add(_live);
  }
}

class FakeProgress implements ProgressRepository {
  final Map<MangaKey, Map<String, bool>> marks = {};
  final Map<MangaKey, ReadingProgress> progress = {};
  final _c = StreamController<MangaKey>.broadcast();

  Stream<T> _live<T>(MangaKey key, T Function() read) async* {
    yield read();
    yield* _c.stream.where((k) => k == key).map((_) => read());
  }

  @override
  Stream<ReadingProgress?> watch(MangaKey key) =>
      _live(key, () => progress[key]);

  @override
  Future<void> record(ReadingProgress p) async {
    progress[p.key] = p;
    _c.add(p.key);
  }

  @override
  Future<void> markRead(MangaKey key, String chapterUrl) async {
    (marks[key] ??= {})[chapterUrl] = true;
    _c.add(key);
  }

  @override
  Future<void> markReadMany(MangaKey key, Iterable<String> urls) async {
    for (final u in urls) {
      (marks[key] ??= {})[u] = true;
    }
    _c.add(key);
  }

  @override
  Future<void> markUnread(MangaKey key, String chapterUrl) async {
    (marks[key] ??= {})[chapterUrl] = false;
    _c.add(key);
  }

  @override
  Stream<Map<String, bool>> readMarks(MangaKey key) =>
      _live(key, () => {...?marks[key]});

  @override
  Stream<Set<String>> readChapters(MangaKey key) => _live(
    key,
    () => {
      for (final e in (marks[key] ?? const <String, bool>{}).entries)
        if (e.value) e.key,
    },
  );
}

class FakeDownloads implements DownloadRepository {
  final List<String> enqueued = [];

  @override
  Future<void> enqueue(MangaKey key, ChapterInfo chapter) async =>
      enqueued.add(chapter.url);

  @override
  Stream<DownloadState> watch(MangaKey key, String chapterUrl) => Stream.value(
    enqueued.contains(chapterUrl)
        ? const DownloadState(status: DownloadStatus.queued)
        : DownloadState.none,
  );

  @override
  Future<List<PageRef>?> offlinePages(MangaKey key, String chapterUrl) async =>
      null;
}
