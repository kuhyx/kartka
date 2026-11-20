/// Which kinds of comics Browse lists (synced setting `browse.contentType`)
/// and the optional source capability that narrows a listing to them
/// (DOCS-contracts §2).
library;

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// The content-type choice, in the toggle's cycle order.
enum ContentType {
  /// Japanese manga only (the default).
  manga,

  /// Manga plus Korean manhwa.
  mangaManhwa,

  /// Everything: no filter is sent (manhua and the rest too).
  all;

  /// The next state of the toggle.
  ContentType get next => values[(index + 1) % values.length];

  /// The value stored as [name], or null for anything else.
  static ContentType? tryParse(String? name) =>
      values.where((t) => t.name == name).firstOrNull;
}

/// One of a source's three listings.
enum Listing {
  /// [MangaSource.popular].
  popular,

  /// [MangaSource.latest].
  latest,

  /// [MangaSource.search].
  search,
}

/// One listing page, and whether the content type was applied to it.
typedef TypedPage = ({SearchPage page, bool applied});

/// A source that can narrow its listings to a [ContentType].
abstract interface class ContentTypeFilterable {
  /// Page [page] of [listing] ([query] for [Listing.search]) narrowed to
  /// [type]. Never called with [ContentType.all]. When this source cannot
  /// narrow this listing it returns the plain page with `applied` false.
  Future<TypedPage> listTyped(
    Listing listing,
    ContentType type,
    int page, {
    String query = '',
  });
}

/// The listing every screen asks for: [ContentType.all] is the plain
/// listing; a [ContentTypeFilterable] source narrows it; any other source
/// answers unfiltered with `applied` false.
Future<TypedPage> listContent(
  MangaSource source,
  Listing listing,
  ContentType type,
  int page, {
  String query = '',
}) async {
  if ((type, source) case (
    != ContentType.all,
    final ContentTypeFilterable typed,
  )) {
    return await typed.listTyped(listing, type, page, query: query);
  }
  final plain = await plainListing(source, listing, page, query);
  return (page: plain, applied: type == ContentType.all);
}

/// [listing] of [source] without any filter.
Future<SearchPage> plainListing(
  MangaSource source,
  Listing listing,
  int page,
  String query,
) => switch (listing) {
  Listing.popular => source.popular(page),
  Listing.latest => source.latest(page),
  Listing.search => source.search(query, page),
};
