/// Which kinds of comics Browse lists (synced setting `browse.contentType`)
/// and the optional source capability that narrows a listing to them
/// (DOCS-contracts §2).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// One kind of comic a listing can hold. A listing entry of unknown kind
/// counts as [manga].
enum ContentType {
  /// Japanese manga (and anything of unknown type).
  manga,

  /// Korean manhwa.
  manhwa,

  /// Chinese manhua.
  manhua,
}

/// The ticked [ContentType]s: [all] (the default) lists everything with no
/// filter sent, [none] lists nothing.
@immutable
class ContentTypes {
  /// A selection of [ticked].
  const new(this.ticked);

  /// Reads the stored value: a JSON list of names (unknown names dropped),
  /// or an old single choice (`manga`, `mangaManhwa`, `all`); null for
  /// anything else.
  static ContentTypes? parse(String? raw) {
    if (_legacy[raw] case final old?) return old;
    try {
      if (jsonDecode(raw ?? '') case final List<Object?> names) {
        return ContentTypes({
          for (final t in ContentType.values)
            if (names.contains(t.name)) t,
        });
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static const Map<String, ContentTypes> _legacy = {
    'manga': ContentTypes({ContentType.manga}),
    'mangaManhwa': ContentTypes({ContentType.manga, ContentType.manhwa}),
    'all': all,
  };

  /// Every type ticked.
  static const all = ContentTypes({
    ContentType.manga,
    ContentType.manhwa,
    ContentType.manhua,
  });

  /// Nothing ticked: an empty listing.
  static const none = ContentTypes({});

  /// The ticked types.
  final Set<ContentType> ticked;

  /// Whether every type is ticked (no filter).
  bool get isAll => ticked.length == ContentType.values.length;

  /// Whether nothing is ticked.
  bool get isNone => ticked.isEmpty;

  /// Whether [type] is ticked.
  bool contains(ContentType type) => ticked.contains(type);

  /// This selection with [type] flipped.
  ContentTypes toggled(ContentType type) => ContentTypes(
    contains(type) ? ({...ticked}..remove(type)) : {...ticked, type},
  );

  /// The stored names, in [ContentType] order.
  List<String> toJson() => [
    for (final t in ContentType.values)
      if (contains(t)) t.name,
  ];

  @override
  bool operator ==(Object other) =>
      other is ContentTypes && setEquals(other.ticked, ticked);

  @override
  int get hashCode => Object.hashAllUnordered(ticked);
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

/// A source that can narrow its listings to some [ContentType]s.
abstract interface class ContentTypeFilterable {
  /// Page [page] of [listing] ([query] for [Listing.search]) narrowed to
  /// [types]. Never called with [ContentTypes.all] or [ContentTypes.none].
  /// When this source cannot narrow this listing it returns the plain page
  /// with `applied` false.
  Future<TypedPage> listTyped(
    Listing listing,
    ContentTypes types,
    int page, {
    String query = '',
  });
}

/// The listing every screen asks for: [ContentTypes.all] is the plain
/// listing, [ContentTypes.none] an empty one; a [ContentTypeFilterable]
/// source narrows the rest; any other source answers unfiltered with
/// `applied` false.
Future<TypedPage> listContent(
  MangaSource source,
  Listing listing,
  ContentTypes types,
  int page, {
  String query = '',
}) async {
  if (types.isNone) return (page: SearchPage.empty, applied: true);
  if ((types.isAll, source) case (false, final ContentTypeFilterable typed)) {
    return await typed.listTyped(listing, types, page, query: query);
  }
  final plain = await plainListing(source, listing, page, query);
  return (page: plain, applied: types.isAll);
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
