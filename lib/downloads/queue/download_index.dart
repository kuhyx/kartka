import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/models.dart';

/// One fully downloaded chapter: how many page blobs and how big.
class OfflineChapter {
  /// Creates a record.
  const new({
    required this.chapter,
    required this.pageCount,
    required this.bytes,
    required this.downloadedAt,
  });

  /// Decodes [toJson].
  factory fromJson(Map<String, Object?> json) => OfflineChapter(
    chapter: ChapterInfo.fromJson(readObject(json['chapter'])),
    pageCount: readInt(json, 'pageCount'),
    bytes: readInt(json, 'bytes'),
    downloadedAt: readDate(json, 'downloadedAt'),
  );

  /// The chapter as it was enqueued (what offline chapter lists show).
  final ChapterInfo chapter;

  /// Chapter identifier in its source.
  String get chapterUrl => chapter.url;

  /// Display name at download time.
  String get chapterName => chapter.name;

  /// Number of page blobs (indexes `0..pageCount-1`).
  final int pageCount;

  /// Sum of the page blob sizes.
  final int bytes;

  /// When the last page was stored.
  final DateTime downloadedAt;

  /// JSON shape.
  Map<String, Object?> toJson() => {
    'chapter': chapter.toJson(),
    'pageCount': pageCount,
    'bytes': bytes,
    'downloadedAt': writeDate(downloadedAt),
  };

  @override
  bool operator ==(Object other) =>
      other is OfflineChapter &&
      other.chapter == chapter &&
      other.pageCount == pageCount &&
      other.bytes == bytes &&
      sameInstant(other.downloadedAt, downloadedAt);

  @override
  int get hashCode =>
      Object.hash(chapter, pageCount, bytes, instantHash(downloadedAt));
}

/// Stored indexes at least this long are decoded in a background isolate.
const int downloadIndexOffUiChars = 64 * 1024;

/// [DownloadIndex.decode] of the stored [raw], off the UI isolate when it
/// is large: the first library paint loads it (every row's offline badge),
/// and an index of thousands of chapters is a long frame on a phone.
Future<DownloadIndex> loadDownloadIndex(String? raw) async =>
    raw == null || raw.length < downloadIndexOffUiChars
    ? DownloadIndex.decode(raw)
    : await compute(DownloadIndex.decode, raw);

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

/// Orders chapters newest first: by number, then upload time (unknown
/// values last), then url so the order is total.
int newestFirst(ChapterInfo a, ChapterInfo b) {
  final byNumber = _desc(a.number, b.number);
  if (byNumber != 0) return byNumber;
  final byDate = _desc(a.uploadedAt, b.uploadedAt);
  return byDate != 0 ? byDate : a.url.compareTo(b.url);
}

int _desc<T extends Comparable<Object>>(T? a, T? b) {
  if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
  return b.compareTo(a);
}
