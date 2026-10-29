import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/sources/suwayomi/legacy_urls.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';

/// Looks up the title kartka knows for [key] (library entry), if any.
typedef TitleLookup = Future<String?> Function(MangaKey key);

/// One Suwayomi source (an installed Tachiyomi extension source).
///
/// Kartka addresses manga and chapters by their Tachiyomi URLs, which are
/// stable across devices and match `.tachibk` entries; the server works on
/// its own integer ids. Ids are cached from every listing, looked up by URL
/// otherwise, and for manga the server has never seen, found by searching
/// the library title on this source and matching the exact URL. URLs an
/// older extension wrote ([LegacyUrls]) are mapped to the server's, and a
/// legacy manga's chapters are listed under their legacy URLs.
class SuwayomiSource implements MangaSource {
  /// Creates the source.
  new({
    required this.info,
    required this.client,
    required this.settings,
    this.titleOf,
  });

  /// Server-side description.
  final SuwayomiSourceInfo info;

  /// GraphQL client.
  final SuwayomiClient client;

  /// Current settings (URL resolution and image auth).
  final SettingsReader settings;

  /// Title lookup for manga the server has not registered yet.
  final TitleLookup? titleOf;

  /// Pages of title search tried before giving up on an unseen manga.
  static const searchPages = 3;

  final _mangaIds = <String, int>{};
  final _chapterIds = <String, int>{};
  late final LegacyUrls? _legacy = legacyUrlsFor(info.serverId);

  String _serverUrl(String url) => _legacy?.mangaUrl(url) ?? url;

  @override
  SourceRef get ref => info.ref;

  @override
  Future<SearchPage> popular(int page) => _list('POPULAR', page);

  @override
  Future<SearchPage> latest(int page) async =>
      info.supportsLatest ? await _list('LATEST', page) : SearchPage.empty;

  @override
  Future<SearchPage> search(String query, int page) =>
      _list('SEARCH', page, query);

  @override
  Future<MangaDetails> details(String mangaUrl) async {
    final data = await client.run(SuwayomiQueries.details, {
      'id': await _mangaId(mangaUrl),
    });
    final payload = data['fetchMangaAndChapters']! as Map<String, Object?>;
    return mangaDetailsFrom(
      {...payload['manga']! as Map<String, Object?>, 'url': mangaUrl},
      ref.id,
      settings().resolve,
    );
  }

  /// Chapters newest first (highest source order first), like Tachiyomi.
  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    final data = await client.run(SuwayomiQueries.chapters, {
      'id': await _mangaId(mangaUrl),
    });
    final payload = data['fetchMangaAndChapters']! as Map<String, Object?>;
    final rows = _maps(payload['chapters'])
      ..sort(
        (a, b) =>
            (b['sourceOrder']! as int).compareTo(a['sourceOrder']! as int),
      );
    final legacy = _serverUrl(mangaUrl) == mangaUrl ? null : _legacy;
    final shown = [
      for (final row in rows)
        if (legacy == null)
          row
        else
          {...row, 'url': legacy.chapterUrl(mangaUrl, row['url']! as String)},
    ];
    for (final row in shown) {
      _chapterIds[row['url']! as String] = row['id']! as int;
    }
    return [for (final row in shown) chapterFrom(row)];
  }

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    final data = await client.run(SuwayomiQueries.pages, {
      'id': await _chapterId(chapterUrl),
    });
    final payload = data['fetchChapterPages']! as Map<String, Object?>;
    final current = settings();
    return pageRefsFrom(
      payload['pages']! as List<Object?>,
      current.resolve,
      current.authHeaders,
    );
  }

  Future<SearchPage> _list(String type, int page, [String? query]) async {
    final data = await client.run(SuwayomiQueries.sourceManga, {
      'source': info.serverId,
      'type': type,
      'page': page,
      'query': ?query,
    });
    final payload = data['fetchSourceManga']! as Map<String, Object?>;
    final rows = _maps(payload['mangas']);
    for (final row in rows) {
      _mangaIds[row['url']! as String] = row['id']! as int;
    }
    final resolve = settings().resolve;
    return SearchPage(
      items: [for (final row in rows) mangaSummaryFrom(row, ref.id, resolve)],
      hasNext: payload['hasNextPage']! as bool,
    );
  }

  Future<int> _mangaId(String url) async {
    final server = _serverUrl(url);
    final cached = _mangaIds[url] ?? _mangaIds[server];
    if (cached != null) return _mangaIds[url] = cached;
    final data = await client.run(SuwayomiQueries.mangaId, {
      'source': info.serverId,
      'url': server,
    });
    final nodes = _maps((data['mangas']! as Map<String, Object?>)['nodes']);
    if (nodes.isNotEmpty) return _mangaIds[url] = nodes.first['id']! as int;
    return _mangaIds[url] = await _searchForUnseen(url, server);
  }

  /// A title search registers its results server-side, which fills
  /// [_mangaIds]; only an exact match of the server's [server] url counts.
  /// The library title is tried first, then a legacy URL's slug (the
  /// source's own romanised title, where the library may hold English).
  Future<int> _searchForUnseen(String url, String server) async {
    final titles = {
      (await titleOf?.call(mangaKeyOf(ref.id, url)))?.trim(),
      _legacy?.searchTitle(url),
    };
    for (final title in titles) {
      if (title == null || title.isEmpty) continue;
      for (var page = 1; page <= searchPages; page++) {
        final result = await search(title, page);
        final id = _mangaIds[server];
        if (id != null) return id;
        if (!result.hasNext) break;
      }
    }
    throw SuwayomiNotOnServerException(ref.id, url);
  }

  Future<int> _chapterId(String url) async {
    final cached = _chapterIds[url];
    if (cached != null) return cached;
    // A legacy chapter url is only known from its manga's listing.
    if (_legacy?.chapter(url) case (final manga, _)) {
      await chapters(manga);
      final listed = _chapterIds[url];
      if (listed != null) return listed;
      throw SuwayomiNotOnServerException(ref.id, url);
    }
    final data = await client.run(SuwayomiQueries.chapterId, {'url': url});
    final nodes = _maps((data['chapters']! as Map<String, Object?>)['nodes']);
    for (final node in nodes) {
      final manga = node['manga']! as Map<String, Object?>;
      if (manga['sourceId'] == info.serverId) {
        return _chapterIds[url] = node['id']! as int;
      }
    }
    throw SuwayomiNotOnServerException(ref.id, url);
  }

  static List<Map<String, Object?>> _maps(Object? list) => [
    for (final e in list! as List<Object?>) e! as Map<String, Object?>,
  ];
}
