import 'package:flutter/foundation.dart';

/// One cell of the Library grid: a library entry joined with the facts the
/// screen sorts and filters on (progress, unread count, downloads, tracking,
/// category membership).
///
/// Library-local view model; the persisted shapes stay in `lib/core/models/`.
@immutable
class LibraryItem {
  /// Creates an item.
  const new({
    required this.key,
    required this.sourceId,
    required this.mangaUrl,
    required this.title,
    required this.addedAt,
    this.coverUrl,
    this.lastReadAt,
    this.unread,
    this.downloaded = false,
    this.tracked = false,
    this.categoryIds = const {},
    this.sourceAvailable = true,
  });

  /// `<sourceId>|<mangaUrl>`.
  final String key;

  /// Source id, used to build the detail route.
  final String sourceId;

  /// Manga url within the source.
  final String mangaUrl;

  /// Display title.
  final String title;

  /// Cover image url, if known.
  final String? coverUrl;

  /// When the entry was added to the library.
  final DateTime addedAt;

  /// When a chapter of it was last read, if ever.
  final DateTime? lastReadAt;

  /// Unread chapter count; `null` when no provider knows it.
  final int? unread;

  /// Whether at least one chapter is stored offline.
  final bool downloaded;

  /// Whether a tracker (AniList/MAL) is bound to it.
  final bool tracked;

  /// Ids of the categories it belongs to.
  final Set<String> categoryIds;

  /// Whether any registered source provider currently offers [sourceId].
  final bool sourceAvailable;

  /// [unread] with unknown treated as zero.
  int get unreadCount => unread ?? 0;

  @override
  bool operator ==(Object other) =>
      other is LibraryItem &&
      other.key == key &&
      other.sourceId == sourceId &&
      other.mangaUrl == mangaUrl &&
      other.title == title &&
      other.coverUrl == coverUrl &&
      other.addedAt == addedAt &&
      other.lastReadAt == lastReadAt &&
      other.unread == unread &&
      other.downloaded == downloaded &&
      other.tracked == tracked &&
      setEquals(other.categoryIds, categoryIds) &&
      other.sourceAvailable == sourceAvailable;

  @override
  int get hashCode => Object.hash(
    key,
    sourceId,
    mangaUrl,
    title,
    coverUrl,
    addedAt,
    lastReadAt,
    unread,
    downloaded,
    tracked,
    Object.hashAllUnordered(categoryIds),
    sourceAvailable,
  );
}
