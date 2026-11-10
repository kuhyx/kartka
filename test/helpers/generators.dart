// glados generators for the core models, shared by property tests.
import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';

/// Characters that stress JSON, URL and key handling.
const _chars = r'aZ09 |/%?#&=:._-"\żółć漫画🙂';

/// Upper bound for generated instants: 2100-01-01 in microseconds.
const _maxMicros = 4102444800000000;

/// Generators for every core model.
extension KartkaAnys on Any {
  /// Strings drawn from [_chars].
  Generator<String> get text => stringOf(_chars);

  /// UTC instants between the epoch and 2100, microsecond precision.
  Generator<DateTime> get instant => intInRange(
    0,
    _maxMicros,
  ).map((us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true));

  /// Chapter-like numbers, including halves.
  Generator<double> get chapterNumber => intInRange(0, 4000).map((n) => n / 2);

  /// String-to-string maps.
  Generator<Map<String, String>> get stringMap => map(text, text);

  /// [SourceRef]s.
  Generator<SourceRef> get sourceRef => combine4(
    text,
    text,
    text,
    choose(SourceOrigin.values),
    (id, name, lang, origin) =>
        SourceRef(id: id, name: name, lang: lang, origin: origin),
  );

  /// [MangaSummary]s.
  Generator<MangaSummary> get mangaSummary => combine4(
    text,
    text,
    text,
    text.nullable,
    (s, u, t, c) => MangaSummary(sourceId: s, url: u, title: t, coverUrl: c),
  );

  /// [MangaDetails]s.
  Generator<MangaDetails> get mangaDetails => combine6(
    mangaSummary,
    list(text),
    text.nullable,
    list(text),
    choose(MangaStatus.values),
    stringMap,
    (m, authors, description, genres, status, trackerIds) => MangaDetails(
      sourceId: m.sourceId,
      url: m.url,
      title: m.title,
      coverUrl: m.coverUrl,
      authors: authors,
      description: description,
      genres: genres,
      status: status,
      trackerIds: trackerIds,
    ),
  );

  /// [ChapterInfo]s.
  Generator<ChapterInfo> get chapterInfo => combine5(
    text,
    text,
    chapterNumber.nullable,
    instant.nullable,
    text.nullable,
    (u, n, no, at, s) =>
        ChapterInfo(url: u, name: n, number: no, uploadedAt: at, scanlator: s),
  );

  /// [PageRef]s.
  Generator<PageRef> get pageRef => combine3(
    intInRange(0, 1000),
    text,
    stringMap,
    (i, url, h) => PageRef(index: i, imageUrl: url, headers: h),
  );

  /// [SearchPage]s.
  Generator<SearchPage> get searchPage => combine2(
    list(mangaSummary),
    this.bool,
    (items, hasNext) => SearchPage(items: items, hasNext: hasNext),
  );

  /// [LibraryEntry]s.
  Generator<LibraryEntry> get libraryEntry => combine6(
    mangaSummary,
    instant,
    instant,
    this.bool,
    text,
    text.nullable,
    (m, added, updated, removed, title, cover) => LibraryEntry(
      key: m.key,
      sourceId: m.sourceId,
      mangaUrl: m.url,
      title: title,
      coverUrl: cover,
      addedAt: added,
      updatedAt: updated,
      removed: removed,
    ),
  );

  /// [Category]s.
  Generator<Category> get category => combine5(
    text,
    text,
    intInRange(-100, 100),
    instant,
    this.bool,
    (id, name, order, at, removed) => Category(
      id: id,
      name: name,
      order: order,
      updatedAt: at,
      removed: removed,
    ),
  );

  /// [ReadingProgress]es.
  Generator<ReadingProgress> get readingProgress => combine6(
    text,
    text,
    chapterNumber,
    intInRange(0, 300),
    instant,
    intInRange(1, 300).nullable,
    (key, url, number, page, at, count) => ReadingProgress(
      key: key,
      chapterUrl: url,
      chapterNumber: number,
      page: page,
      readAt: at,
      pageCount: count,
    ),
  );

  /// [DownloadState]s.
  Generator<DownloadState> get downloadState => combine4(
    choose(DownloadStatus.values),
    intInRange(0, 500),
    intInRange(0, 500),
    text.nullable,
    (s, done, total, error) => DownloadState(
      status: s,
      pagesDone: done,
      pagesTotal: total,
      error: error,
    ),
  );
}
