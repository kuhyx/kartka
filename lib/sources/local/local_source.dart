import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/local_library.dart';

/// Thrown when a manga or chapter is not imported on this device (e.g. a
/// synced library entry whose CBZ only exists on the other device).
class LocalNotImportedException implements Exception {
  /// Creates the exception for the missing [url].
  const new(this.url);

  /// The manga or chapter url that is not in the local index.
  final String url;

  @override
  String toString() =>
      'LocalNotImportedException: $url is not imported on this device';
}

/// The `local` source: CBZ/ZIP archives and image folders imported into the
/// BlobStore. Everything fits on one page, so `hasNext` is always false.
class LocalSource implements MangaSource {
  /// Serves the manga in [library].
  const new(this.library);

  /// The import store this source reads.
  final LocalLibrary library;

  /// Stable source id (DOCS-contracts §1).
  static const id = 'local';

  @override
  SourceRef get ref => const SourceRef(
    id: id,
    name: 'Local files',
    lang: 'all',
    origin: SourceOrigin.local,
  );

  @override
  Future<SearchPage> popular(int page) async =>
      _page(page, (await library.load()).manga);

  @override
  Future<SearchPage> latest(int page) async {
    final manga = (await library.load()).manga
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _page(page, manga);
  }

  @override
  Future<SearchPage> search(String query, int page) async {
    final q = seriesKey(query);
    final manga = (await library.load()).manga.where(
      (m) => seriesKey(m.title).contains(q),
    );
    return _page(page, manga);
  }

  @override
  Future<MangaDetails> details(String mangaUrl) async {
    final m = await _manga(mangaUrl);
    final n = m.chapters.length;
    return MangaDetails(
      sourceId: id,
      url: m.url,
      title: m.title,
      coverUrl: _cover(m),
      description:
          '$n ${n == 1 ? 'chapter' : 'chapters'} imported on '
          'this device',
    );
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    final m = await _manga(mangaUrl);
    return [
      for (final c in m.chapters.reversed)
        ChapterInfo(
          url: c.url,
          name: c.title,
          number: c.number,
          uploadedAt: c.importedAt,
        ),
    ];
  }

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    final chapter = (await library.load()).findChapter(chapterUrl);
    if (chapter == null) throw LocalNotImportedException(chapterUrl);
    final keys = chapter.pageBlobKeys;
    return [
      for (var i = 0; i < keys.length; i++)
        PageRef(index: i, imageUrl: blobPageUrl(keys[i])),
    ];
  }

  Future<LocalManga> _manga(String url) async =>
      (await library.load()).find(url) ??
      (throw LocalNotImportedException(url));

  SearchPage _page(int page, Iterable<LocalManga> manga) => SearchPage(
    items: page > 1
        ? const []
        : [
            for (final m in manga)
              MangaSummary(
                sourceId: id,
                url: m.url,
                title: m.title,
                coverUrl: _cover(m),
              ),
          ],
    hasNext: false,
  );

  String? _cover(LocalManga m) => switch (m.coverBlobKey) {
    final key? => blobPageUrl(key),
    null => null,
  };
}
