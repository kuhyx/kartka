import 'package:collection/collection.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/manga.dart';

const _items = ListEquality<MangaSummary>();

/// One page of popular / latest / search results (DOCS-contracts §1).
class SearchPage {
  /// Creates a result page.
  const new({required this.items, required this.hasNext});

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => SearchPage(
    items: List.unmodifiable(
      (json['items']! as List<Object?>).map(
        (raw) => MangaSummary.fromJson(readObject(raw)),
      ),
    ),
    hasNext: readBool(json, 'hasNext'),
  );

  /// An empty last page.
  static const empty = SearchPage(items: [], hasNext: false);

  /// Results on this page, in source order.
  final List<MangaSummary> items;

  /// Whether requesting the next page may return more results.
  final bool hasNext;

  /// JSON shape: items as summary objects.
  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'hasNext': hasNext,
  };

  @override
  bool operator ==(Object other) =>
      other is SearchPage &&
      other.hasNext == hasNext &&
      _items.equals(other.items, items);

  @override
  int get hashCode => Object.hash(hasNext, _items.hash(items));

  @override
  String toString() => 'SearchPage(${items.length}, hasNext: $hasNext)';
}
