import 'package:flutter/foundation.dart' show immutable, listEquals;

/// One imported chapter: display data plus the BlobStore keys of its pages.
@immutable
class LocalChapter {
  /// Creates a chapter record.
  const new({
    required this.url,
    required this.sourceName,
    required this.title,
    required this.pageBlobKeys,
    required this.importedAt,
    this.number,
  });

  /// Decodes [toJson] output; throws on a malformed map.
  factory fromJson(Map<String, Object?> j) => LocalChapter(
    url: j['url']! as String,
    sourceName: j['sourceName']! as String,
    title: j['title']! as String,
    number: (j['number'] as num?)?.toDouble(),
    pageBlobKeys: [for (final k in j['pages']! as List<Object?>) k! as String],
    importedAt: DateTime.fromMillisecondsSinceEpoch(
      j['importedAt']! as int,
      isUtc: true,
    ),
  );

  /// Content-derived chapter url: `<seriesKey>/<chapterKey>`.
  final String url;

  /// Archive stem or folder name; orders chapters that lack a number.
  final String sourceName;

  /// Display name.
  final String title;

  /// ComicInfo `Number`, when known.
  final double? number;

  /// BlobStore keys of the pages, in reading order.
  final List<String> pageBlobKeys;

  /// When this chapter was (last) imported.
  final DateTime importedAt;

  /// JSON form for the KeyValueStore index.
  Map<String, Object?> toJson() => {
    'url': url,
    'sourceName': sourceName,
    'title': title,
    'number': number,
    'pages': pageBlobKeys,
    'importedAt': importedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is LocalChapter &&
      other.url == url &&
      other.sourceName == sourceName &&
      other.title == title &&
      other.number == number &&
      other.importedAt == importedAt &&
      listEquals(other.pageBlobKeys, pageBlobKeys);

  @override
  int get hashCode => Object.hash(
    url,
    sourceName,
    title,
    number,
    importedAt,
    Object.hashAll(pageBlobKeys),
  );
}

/// One local series: every imported chapter sharing a [url] (series key).
@immutable
class LocalManga {
  /// Creates a manga record; [chapters] must already be in reading order.
  const new({required this.url, required this.title, required this.chapters});

  /// Decodes [toJson] output; throws on a malformed map.
  factory fromJson(Map<String, Object?> j) => LocalManga(
    url: j['url']! as String,
    title: j['title']! as String,
    chapters: [
      for (final c in j['chapters']! as List<Object?>)
        LocalChapter.fromJson(c! as Map<String, Object?>),
    ],
  );

  /// The normalised series key; also the MangaSource `mangaUrl`.
  final String url;

  /// Display title (first-seen spelling of the series).
  final String title;

  /// Chapters in reading order (never empty in a stored index).
  final List<LocalChapter> chapters;

  /// First page of the first chapter, used as the cover.
  String? get coverBlobKey => chapters.firstOrNull?.pageBlobKeys.firstOrNull;

  /// Latest chapter import time.
  DateTime get updatedAt =>
      chapters.map((c) => c.importedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  /// JSON form for the KeyValueStore index.
  Map<String, Object?> toJson() => {
    'url': url,
    'title': title,
    'chapters': [for (final c in chapters) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is LocalManga &&
      other.url == url &&
      other.title == title &&
      listEquals(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(url, title, Object.hashAll(chapters));
}
