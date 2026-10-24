import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/manga_key.dart';

/// A manga in the user's library (DOCS-contracts §8; synced per §4).
///
/// Removal is a tombstone ([removed]) rather than a delete, so it merges
/// last-writer-wins on [updatedAt] like every other field.
class LibraryEntry {
  /// Creates an entry.
  const new({
    required this.key,
    required this.sourceId,
    required this.mangaUrl,
    required this.title,
    required this.addedAt,
    required this.updatedAt,
    this.coverUrl,
    this.removed = false,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => LibraryEntry(
    key: readString(json, 'key'),
    sourceId: readString(json, 'sourceId'),
    mangaUrl: readString(json, 'mangaUrl'),
    title: readString(json, 'title'),
    coverUrl: readOptString(json, 'coverUrl'),
    addedAt: readDate(json, 'addedAt'),
    updatedAt: readDate(json, 'updatedAt'),
    removed: readBool(json, 'removed'),
  );

  /// `'<sourceId>|<mangaUrl>'`.
  final MangaKey key;

  /// Source the manga is read from.
  final String sourceId;

  /// The source's identifier for the manga.
  final String mangaUrl;

  /// Display title.
  final String title;

  /// Cover image URL, when known.
  final String? coverUrl;

  /// When the manga was first added.
  final DateTime addedAt;

  /// Last-writer-wins clock for the entry.
  final DateTime updatedAt;

  /// Tombstone: the entry was removed from the library.
  final bool removed;

  /// Copy with the given fields replaced.
  LibraryEntry copyWith({
    String? title,
    String? coverUrl,
    DateTime? updatedAt,
    bool? removed,
  }) => LibraryEntry(
    key: key,
    sourceId: sourceId,
    mangaUrl: mangaUrl,
    title: title ?? this.title,
    coverUrl: coverUrl ?? this.coverUrl,
    addedAt: addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    removed: removed ?? this.removed,
  );

  /// JSON shape; instants as UTC ISO-8601.
  Map<String, Object?> toJson() => {
    'key': key,
    'sourceId': sourceId,
    'mangaUrl': mangaUrl,
    'title': title,
    'coverUrl': coverUrl,
    'addedAt': writeDate(addedAt),
    'updatedAt': writeDate(updatedAt),
    'removed': removed,
  };

  @override
  bool operator ==(Object other) =>
      other is LibraryEntry &&
      other.key == key &&
      other.sourceId == sourceId &&
      other.mangaUrl == mangaUrl &&
      other.title == title &&
      other.coverUrl == coverUrl &&
      sameInstant(other.addedAt, addedAt) &&
      sameInstant(other.updatedAt, updatedAt) &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(
    key,
    sourceId,
    mangaUrl,
    title,
    coverUrl,
    instantHash(addedAt),
    instantHash(updatedAt),
    removed,
  );

  @override
  String toString() => 'LibraryEntry($key${removed ? ', removed' : ''})';
}
