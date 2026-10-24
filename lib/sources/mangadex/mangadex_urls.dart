import 'package:kartka/sources/mangadex/mangadex_settings.dart';

/// Builds MangaDex API URLs from the current settings.
///
/// Stored urls follow the Keiyoushi MangaDex extension (`/manga/<uuid>`,
/// `/chapter/<uuid>`), so `.tachibk` entries map onto this source unchanged.
class MangadexUrls {
  /// Creates a builder bound to [settings].
  const new(this.settings);

  /// API host (rate-limited, needs a real User-Agent).
  static const apiHost = 'api.mangadex.org';

  /// Browse page size, as the Tachiyomi extension uses.
  static const pageSize = 20;

  /// Largest page the chapter feed allows.
  static const feedLimit = 500;

  /// MangaDex rejects any listing with `offset + limit` above this.
  static const maxWindow = 10000;

  static const _kinds = {'manga', 'chapter', 'title'};

  /// Settings that decide languages and ratings.
  final MangadexSettings settings;

  /// Most-followed manga.
  Uri popular(int page) => _browse(page, {'order[followedCount]': 'desc'});

  /// Manga with the newest uploaded chapter first.
  Uri latest(int page) =>
      _browse(page, {'order[latestUploadedChapter]': 'desc'});

  /// Title search ordered by relevance.
  Uri search(String query, int page) =>
      _browse(page, {'title': query, 'order[relevance]': 'desc'});

  /// Offset of 1-based [page]; pages below 1 mean the first.
  static int offsetOf(int page) => (page < 1 ? 0 : page - 1) * pageSize;

  Uri _browse(int page, Map<String, Object> extra) =>
      Uri.https(apiHost, '/manga', {
        'limit': '$pageSize',
        'offset': '${offsetOf(page)}',
        'includes[]': ['cover_art'],
        'contentRating[]': settings.ratingNames,
        'availableTranslatedLanguage[]': settings.languages,
        'hasAvailableChapters': 'true',
        ...extra,
      });

  /// One manga with cover, authors and artists resolved.
  Uri details(String id) => Uri.https(apiHost, '/manga/$id', {
    'includes[]': ['cover_art', 'author', 'artist'],
  });

  /// One page of a manga's chapter feed.
  ///
  /// Every rating is asked for: the rating filter is a browsing choice, and
  /// a manga already opened must show all of its chapters.
  Uri feed(String id, {required int offset, int limit = feedLimit}) =>
      Uri.https(apiHost, '/manga/$id/feed', {
        'limit': '$limit',
        'offset': '$offset',
        'translatedLanguage[]': settings.languages,
        'contentRating[]': [for (final r in ContentRating.values) r.name],
        'includes[]': ['scanlation_group'],
        'includeExternalUrl': '0',
        'includeEmptyPages': '0',
        'includeFuturePublishAt': '0',
        'order[volume]': 'desc',
        'order[chapter]': 'desc',
      });

  /// MangaDex@Home server for a chapter; its `baseUrl` expires in minutes.
  Uri atHome(String chapterId) =>
      Uri.https(apiHost, '/at-home/server/$chapterId');

  /// URL of one page image on a MangaDex@Home node.
  static String pageImage(
    String baseUrl,
    String hash,
    String file, {
    bool dataSaver = false,
  }) => '$baseUrl/${dataSaver ? 'data-saver' : 'data'}/$hash/$file';

  /// 512 px cover thumbnail.
  static String cover(String mangaId, String fileName) =>
      'https://uploads.mangadex.org/covers/$mangaId/$fileName.512.jpg';

  /// Stored url of a manga.
  static String mangaUrl(String id) => '/manga/$id';

  /// Stored url of a chapter.
  static String chapterUrl(String id) => '/chapter/$id';

  /// Id inside a stored url, a mangadex.org web url, or a bare id.
  static String idOf(String url) {
    final segs = Uri.parse(url).pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (segs.length == 1 && !_kinds.contains(segs.single)) return segs.single;
    final i = segs.indexWhere(_kinds.contains);
    if (i >= 0 && i + 1 < segs.length) return segs[i + 1];
    throw FormatException('Not a MangaDex url', url);
  }
}
