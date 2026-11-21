import 'package:flutter/foundation.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/core/source/manga_source.dart';

/// One source's listings under the content-type setting: every page asks
/// [listContent] with the setting's value at fetch time, and [applied]
/// remembers, per listing, whether the source could narrow it.
class TypedListings {
  /// Creates the listings of [source] following [type].
  new(this.source, this.type);

  /// The listed source.
  final MangaSource source;

  /// The content-type setting.
  final ValueListenable<ContentTypes> type;

  /// Whether the last page of each listing was narrowed; a listing not
  /// fetched yet is absent.
  final applied = ValueNotifier<Map<Listing, bool>>(const {});

  /// [applied] for [listing]: true until a page says otherwise.
  bool appliedTo(Listing listing) => applied.value[listing] ?? true;

  /// Pages of [listing] ([query] for search).
  PageFetcher<MangaSummary> fetcher(Listing listing, [String query = '']) =>
      (page) async {
        final asked = type.value;
        final r = await listContent(source, listing, asked, page, query: query);
        // A page of the previous setting (dropped by the reset) says nothing.
        if (type.value == asked && applied.value[listing] != r.applied) {
          applied.value = {...applied.value, listing: r.applied};
        }
        return (items: r.page.items, hasNext: r.page.hasNext);
      };

  /// Releases [applied].
  void dispose() => applied.dispose();
}
