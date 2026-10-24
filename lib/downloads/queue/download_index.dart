import 'dart:convert';

import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/manga_key.dart';

/// One fully downloaded chapter: how many page blobs and how big.
class OfflineChapter {
  /// Creates a record.
  const new({
    required this.chapterUrl,
    required this.chapterName,
    required this.pageCount,
    required this.bytes,
    required this.downloadedAt,
  });

  /// Decodes [toJson].
  factory fromJson(Map<String, Object?> json) => OfflineChapter(
    chapterUrl: readString(json, 'chapterUrl'),
    chapterName: readString(json, 'chapterName'),
    pageCount: readInt(json, 'pageCount'),
    bytes: readInt(json, 'bytes'),
    downloadedAt: readDate(json, 'downloadedAt'),
  );

  /// Chapter identifier in its source.
  final String chapterUrl;

  /// Display name at download time.
  final String chapterName;

  /// Number of page blobs (indexes `0..pageCount-1`).
  final int pageCount;

  /// Sum of the page blob sizes.
  final int bytes;

  /// When the last page was stored.
  final DateTime downloadedAt;

  /// JSON shape.
  Map<String, Object?> toJson() => {
    'chapterUrl': chapterUrl,
    'chapterName': chapterName,
    'pageCount': pageCount,
    'bytes': bytes,
    'downloadedAt': writeDate(downloadedAt),
  };

  @override
  bool operator ==(Object other) =>
      other is OfflineChapter &&
      other.chapterUrl == chapterUrl &&
      other.chapterName == chapterName &&
      other.pageCount == pageCount &&
      other.bytes == bytes &&
      sameInstant(other.downloadedAt, downloadedAt);

  @override
  int get hashCode => Object.hash(
    chapterUrl,
    chapterName,
    pageCount,
    bytes,
    instantHash(downloadedAt),
  );
}

/// Which chapters are stored offline, per manga (persisted in KeyValueStore).
class DownloadIndex {
  /// An empty index.
  new();

  /// Decodes [encode]'s output; `null` is empty.
  factory decode(String? raw) {
    final idx = DownloadIndex();
    if (raw == null) return idx;
    readObject(jsonDecode(raw)).forEach((key, chapters) {
      for (final c in chapters! as List<Object?>) {
        idx.put(key, OfflineChapter.fromJson(readObject(c)));
      }
    });
    return idx;
  }

  final Map<MangaKey, Map<String, OfflineChapter>> _byManga = {};

  /// Manga with at least one offline chapter.
  List<MangaKey> get mangaKeys => List.unmodifiable(_byManga.keys);

  /// Offline chapters of [key] in download order.
  List<OfflineChapter> chapters(MangaKey key) =>
      List.unmodifiable(_byManga[key]?.values ?? const <OfflineChapter>[]);

  /// The record for one chapter, if it is offline.
  OfflineChapter? chapter(MangaKey key, String chapterUrl) =>
      _byManga[key]?[chapterUrl];

  /// Bytes stored for [key].
  int mangaBytes(MangaKey key) =>
      chapters(key).fold(0, (sum, c) => sum + c.bytes);

  /// Bytes stored for every manga.
  int get totalBytes => _byManga.keys.fold(0, (s, k) => s + mangaBytes(k));

  /// Records (or replaces) an offline chapter.
  void put(MangaKey key, OfflineChapter chapter) =>
      (_byManga[key] ??= {})[chapter.chapterUrl] = chapter;

  /// Forgets one chapter and returns it.
  OfflineChapter? removeChapter(MangaKey key, String chapterUrl) {
    final chapters = _byManga[key];
    final removed = chapters?.remove(chapterUrl);
    if (chapters != null && chapters.isEmpty) _byManga.remove(key);
    return removed;
  }

  /// Forgets every chapter of [key] and returns them.
  List<OfflineChapter> removeManga(MangaKey key) =>
      _byManga.remove(key)?.values.toList() ?? const [];

  /// JSON string for KeyValueStore.
  String encode() => jsonEncode({
    for (final e in _byManga.entries)
      e.key: [for (final c in e.value.values) c.toJson()],
  });
}
