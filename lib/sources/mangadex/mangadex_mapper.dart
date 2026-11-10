import 'package:kartka/core/models/models.dart';
import 'package:kartka/sources/mangadex/mangadex_parse.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_urls.dart';

/// Source id of the native MangaDex source.
const mangadexSourceId = 'mangadex';

/// Display name of the native MangaDex source: content (a source name), so
/// its settings tile may paint it.
const mangadexSourceName = 'MangaDex';

const Map<String, MangaStatus> _status = {
  'ongoing': MangaStatus.ongoing,
  'completed': MangaStatus.completed,
  'hiatus': MangaStatus.onHiatus,
  'cancelled': MangaStatus.cancelled,
};

/// Maps decoded MangaDex JSON onto the core models.
class MangadexMapper {
  /// Creates a mapper using [settings] for language preference.
  const new(this.settings);

  /// Picks titles and descriptions.
  final MangadexSettings settings;

  String _id(Json item) => item['id']! as String;

  Json _attrs(Json item) => item['attributes'] as Json? ?? const {};

  String? _cover(Json item) {
    final file = coverFile(item);
    return file == null ? null : MangadexUrls.cover(_id(item), file);
  }

  /// A manga entity as a list item.
  MangaSummary summary(Json item) => MangaSummary(
    sourceId: mangadexSourceId,
    url: MangadexUrls.mangaUrl(_id(item)),
    title: pickTitle(_attrs(item), settings.languages),
    coverUrl: _cover(item),
  );

  /// A manga entity with authors, artists and tracker links.
  MangaDetails details(Json item) {
    final attrs = _attrs(item);
    return MangaDetails(
      sourceId: mangadexSourceId,
      url: MangadexUrls.mangaUrl(_id(item)),
      title: pickTitle(attrs, settings.languages),
      coverUrl: _cover(item),
      authors: {
        ...relNames(item, 'author'),
        ...relNames(item, 'artist'),
      }.toList(),
      description: pickDescription(attrs, settings.languages),
      genres: tagNames(attrs),
      status: _status[attrs['status']] ?? MangaStatus.unknown,
      trackerIds: trackerIds(attrs),
    );
  }

  /// A `/manga` list response at [offset].
  SearchPage page(Json body, int offset) {
    final data = (body['data'] as List<Object?>? ?? const []).cast<Json>();
    final total = (body['total'] as num?)?.toInt() ?? 0;
    final more = offset + data.length < total;
    final fits = offset + 2 * MangadexUrls.pageSize <= MangadexUrls.maxWindow;
    return SearchPage(
      items: List.unmodifiable(data.map(summary)),
      hasNext: more && fits,
    );
  }

  /// A chapter entity.
  ChapterInfo chapter(Json item) {
    final attrs = _attrs(item);
    return ChapterInfo(
      url: MangadexUrls.chapterUrl(_id(item)),
      name: chapterName(attrs),
      number: chapterNumber(attrs),
      uploadedAt: publishedAt(attrs),
      scanlator: scanlator(item),
    );
  }

  /// Page images of an `/at-home/server` response.
  ///
  /// Falls back to full quality when a chapter has no data-saver set.
  List<PageRef> pages(Json body, Map<String, String> headers) {
    final base = body['baseUrl']! as String;
    final ch = body['chapter']! as Json;
    final hash = ch['hash']! as String;
    final saver = (ch['dataSaver'] as List<Object?>? ?? const [])
        .cast<String>();
    final useSaver = settings.dataSaver && saver.isNotEmpty;
    final files = useSaver
        ? saver
        : (ch['data'] as List<Object?>? ?? const []).cast<String>();
    return [
      for (final (i, f) in files.indexed)
        PageRef(
          index: i,
          imageUrl: MangadexUrls.pageImage(base, hash, f, dataSaver: useSaver),
          headers: headers,
        ),
    ];
  }
}
