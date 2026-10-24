import 'package:flutter/foundation.dart';
import 'package:kartka/library/state/library_item.dart';

/// Library sort keys.
enum LibrarySort {
  /// Alphabetical, case-insensitive (A first when ascending).
  title,

  /// Most recently read first when ascending; never-read entries last.
  lastRead,

  /// Newest addition first when ascending.
  dateAdded,

  /// Most unread chapters first when ascending.
  unread,
}

/// What the Library screen shows: one category tab, filters, search, sort.
@immutable
class LibraryQuery {
  /// Creates a query; the default shows everything sorted by title.
  const new({
    this.sort = LibrarySort.title,
    this.ascending = true,
    this.unreadOnly = false,
    this.downloadedOnly = false,
    this.trackedOnly = false,
    this.categoryId,
    this.search = '',
  });

  /// Sort key.
  final LibrarySort sort;

  /// `false` reverses [sort]'s natural direction.
  final bool ascending;

  /// Keep only entries with unread chapters.
  final bool unreadOnly;

  /// Keep only entries with offline chapters.
  final bool downloadedOnly;

  /// Keep only entries bound to a tracker.
  final bool trackedOnly;

  /// Category tab; `null` is the "All" tab.
  final String? categoryId;

  /// Title search text.
  final String search;

  /// Returns a copy with the given fields replaced.
  LibraryQuery copyWith({
    LibrarySort? sort,
    bool? ascending,
    bool? unreadOnly,
    bool? downloadedOnly,
    bool? trackedOnly,
    String? categoryId,
    bool clearCategory = false,
    String? search,
  }) => LibraryQuery(
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    unreadOnly: unreadOnly ?? this.unreadOnly,
    downloadedOnly: downloadedOnly ?? this.downloadedOnly,
    trackedOnly: trackedOnly ?? this.trackedOnly,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    search: search ?? this.search,
  );

  /// Whether [item] passes the tab, every filter and the search.
  bool matches(LibraryItem item) {
    final needle = search.trim().toLowerCase();
    return (categoryId == null || item.categoryIds.contains(categoryId)) &&
        (!unreadOnly || item.unreadCount > 0) &&
        (!downloadedOnly || item.downloaded) &&
        (!trackedOnly || item.tracked) &&
        (needle.isEmpty || item.title.toLowerCase().contains(needle));
  }

  /// Total order used for display. Ties on the sort key fall back to title
  /// and then key, so the result never depends on input order.
  int compare(LibraryItem a, LibraryItem b) {
    final primary = _primary(a, b);
    final ordered = ascending ? primary : -primary;
    if (ordered != 0) return ordered;
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.key.compareTo(b.key);
  }

  int _primary(LibraryItem a, LibraryItem b) => switch (sort) {
    LibrarySort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    LibrarySort.lastRead => _newestFirst(a.lastReadAt, b.lastReadAt),
    LibrarySort.dateAdded => b.addedAt.compareTo(a.addedAt),
    LibrarySort.unread => b.unreadCount.compareTo(a.unreadCount),
  };

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return (a == null ? 1 : 0) - (b == null ? 1 : 0);
    }
    return b.compareTo(a);
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.unreadOnly == unreadOnly &&
      other.downloadedOnly == downloadedOnly &&
      other.trackedOnly == trackedOnly &&
      other.categoryId == categoryId &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    sort,
    ascending,
    unreadOnly,
    downloadedOnly,
    trackedOnly,
    categoryId,
    search,
  );
}

/// Filters and sorts [items] for display.
List<LibraryItem> applyQuery(List<LibraryItem> items, LibraryQuery query) =>
    items.where(query.matches).toList()..sort(query.compare);
