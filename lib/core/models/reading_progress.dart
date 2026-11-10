import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/manga_key.dart';

/// How far the user has read a manga (DOCS-contracts §8; synced per §4).
///
/// Progress never decreases: [isAheadOf] is the single ordering every
/// repository, the sync merge and the trackers agree on.
class ReadingProgress {
  /// Creates a progress record.
  const new({
    required this.key,
    required this.chapterUrl,
    required this.chapterNumber,
    required this.page,
    required this.readAt,
    this.pageCount,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => ReadingProgress(
    key: readString(json, 'key'),
    chapterUrl: readString(json, 'chapterUrl'),
    chapterNumber: readDouble(json, 'chapterNumber'),
    page: readInt(json, 'page'),
    readAt: readDate(json, 'readAt'),
    pageCount: (json['pageCount'] as num?)?.toInt(),
  );

  /// The manga.
  final MangaKey key;

  /// The chapter currently being read.
  final String chapterUrl;

  /// That chapter's number (decimals allowed).
  final double chapterNumber;

  /// Zero-based page within the chapter.
  final int page;

  /// When this position was reached.
  final DateTime readAt;

  /// Pages in [chapterUrl] when this was recorded; null when unknown
  /// (written before it existed, or by an import or a tracker).
  final int? pageCount;

  /// Whether this is strictly further than [other]: a higher chapter, or the
  /// same chapter and a later page. Anything is ahead of `null`.
  bool isAheadOf(ReadingProgress? other) {
    if (other == null) return true;
    if (chapterNumber != other.chapterNumber) {
      return chapterNumber > other.chapterNumber;
    }
    return page > other.page;
  }

  /// JSON shape; [readAt] as UTC ISO-8601.
  Map<String, Object?> toJson() => {
    'key': key,
    'chapterUrl': chapterUrl,
    'chapterNumber': chapterNumber,
    'page': page,
    'readAt': writeDate(readAt),
    'pageCount': ?pageCount,
  };

  @override
  bool operator ==(Object other) =>
      other is ReadingProgress &&
      other.key == key &&
      other.chapterUrl == chapterUrl &&
      other.chapterNumber == chapterNumber &&
      other.page == page &&
      other.pageCount == pageCount &&
      sameInstant(other.readAt, readAt);

  @override
  int get hashCode => Object.hash(
    key,
    chapterUrl,
    chapterNumber,
    page,
    pageCount,
    instantHash(readAt),
  );

  @override
  String toString() => 'ReadingProgress($key, ch $chapterNumber p $page)';
}
