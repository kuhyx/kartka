/// Library URLs an older version of an extension wrote, mapped to the ones
/// the installed version uses (the server only knows the current ones).
library;

/// Server source id of AllManga (`eu.kanade.tachiyomi.extension.en.allanime`).
const allMangaServerId = '4709139914729853090';

/// The legacy URL scheme of the source with server id [serverId], if any.
LegacyUrls? legacyUrlsFor(String serverId) =>
    serverId == allMangaServerId ? const AllMangaLegacyUrls() : null;

/// One source's legacy manga and chapter URLs.
abstract interface class LegacyUrls {
  /// The server's url for legacy manga [url]; null when [url] is current.
  String? mangaUrl(String url);

  /// Words to search for legacy manga [url] (its slug); null when none.
  String? searchTitle(String url);

  /// The legacy url of the server's chapter [chapterUrl] of [mangaUrl].
  String chapterUrl(String mangaUrl, String chapterUrl);

  /// The legacy manga url and the server's chapter url of legacy chapter
  /// [url]; null when [url] is current.
  (String, String)? chapter(String url);
}

/// AllManga before its id-only URLs: manga `/manga/<id>/<slug>` is now
/// `<id>`, chapter `/read/<id>/<slug>/chapter-<n>-sub` is now `<n>`
/// (kuhy's `.tachibk` read marks all use `-sub`). Chapters of a legacy
/// manga keep the legacy form, so read marks and stored lists match.
class AllMangaLegacyUrls implements LegacyUrls {
  /// The scheme (stateless).
  const new();

  static final _manga = RegExp(r'^/manga/([A-Za-z0-9]+)/([^/]*)$');
  static final _chapter = RegExp(
    r'^/read/([A-Za-z0-9]+)/([^/]*)/chapter-(.+)-sub$',
  );

  @override
  String? mangaUrl(String url) => _manga.firstMatch(url)?.group(1);

  @override
  String? searchTitle(String url) {
    final slug = _manga.firstMatch(url)?.group(2)?.replaceAll('-', ' ').trim();
    return slug == null || slug.isEmpty ? null : slug;
  }

  @override
  String chapterUrl(String mangaUrl, String chapterUrl) {
    final m = _manga.firstMatch(mangaUrl)!;
    return '/read/${m.group(1)}/${m.group(2)}/chapter-$chapterUrl-sub';
  }

  @override
  (String, String)? chapter(String url) {
    final m = _chapter.firstMatch(url);
    if (m == null) return null;
    return ('/manga/${m.group(1)}/${m.group(2)}', m.group(3)!);
  }
}
