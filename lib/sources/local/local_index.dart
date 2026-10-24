import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:kartka/sources/local/archive_scan.dart';
import 'package:kartka/sources/local/local_records.dart';
import 'package:kartka/sources/local/natural_sort.dart';

export 'package:kartka/sources/local/local_records.dart';

/// Result of changing the index: the new index plus BlobStore keys that no
/// chapter references any more (the caller deletes them).
typedef IndexChange = ({LocalIndex index, List<String> orphanBlobKeys});

/// Normalised series key: trimmed, lowercase, single spaces. Two archives
/// whose series differ only in case/spacing land in the same manga.
String seriesKey(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _displayTitle(String title) =>
    title.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Content-derived chapter url. The same file imported on two devices gets
/// the same url, so progress syncs (MangaKey = `local|<seriesKey>`).
String chapterUrlFor(ScannedChapter c) =>
    '${seriesKey(c.seriesTitle)}/${seriesKey(c.name)}';

/// Reading order: numbered chapters by number, then the rest; ties by the
/// natural order of the archive/folder name.
int _readingOrder(LocalChapter a, LocalChapter b) {
  final byNumber = (a.number ?? double.infinity).compareTo(
    b.number ?? double.infinity,
  );
  return byNumber != 0 ? byNumber : naturalCompare(a.sourceName, b.sourceName);
}

/// Every locally imported manga, persisted as JSON in the KeyValueStore.
@immutable
class LocalIndex {
  /// An index with no manga.
  const new empty() : _byUrl = const {};

  const new _(this._byUrl);

  /// Decodes `jsonEncode(toJson())` output. Missing or malformed data yields
  /// an empty index (BlobStore pages stay; re-importing rebuilds entries).
  factory decode(String? json) {
    if (json == null) return const LocalIndex.empty();
    try {
      final map = jsonDecode(json) as Map<String, Object?>;
      final manga = [
        for (final m in map['manga']! as List<Object?>)
          LocalManga.fromJson(m! as Map<String, Object?>),
      ];
      return LocalIndex._({for (final m in manga) m.url: m});
    } on Object {
      return const LocalIndex.empty();
    }
  }

  final Map<String, LocalManga> _byUrl;

  /// All manga, in natural title order.
  List<LocalManga> get manga => naturalSortedBy(_byUrl.values, (m) => m.title);

  /// The manga with series key [url], if imported.
  LocalManga? find(String url) => _byUrl[url];

  /// The chapter with [chapterUrl], if imported.
  LocalChapter? findChapter(String chapterUrl) {
    // The chapter key is a file stem or folder basename and never holds a
    // '/', while a series (ComicInfo `Fate/Zero`) may: split on the last one.
    final slash = chapterUrl.lastIndexOf('/');
    final manga = slash < 0 ? null : find(chapterUrl.substring(0, slash));
    return manga?.chapters.where((c) => c.url == chapterUrl).firstOrNull;
  }

  /// Adds (or replaces) chapter [c] whose pages were stored under [blobKeys].
  IndexChange add(ScannedChapter c, List<String> blobKeys, DateTime now) {
    final chapter = LocalChapter(
      url: chapterUrlFor(c),
      sourceName: c.name,
      title: c.chapterTitle,
      number: c.info?.number,
      pageBlobKeys: blobKeys,
      importedAt: now,
    );
    final key = seriesKey(c.seriesTitle);
    final old = _byUrl[key];
    final previous = old?.chapters.where((x) => x.url == chapter.url);
    final kept = old?.chapters.where((x) => x.url != chapter.url) ?? const [];
    final manga = LocalManga(
      url: key,
      title: old?.title ?? _displayTitle(c.seriesTitle),
      chapters: [...kept, chapter]..sort(_readingOrder),
    );
    final orphans = [
      for (final p in previous ?? const <LocalChapter>[])
        ...p.pageBlobKeys.where((k) => !blobKeys.contains(k)),
    ];
    return (
      index: LocalIndex._({..._byUrl, key: manga}),
      orphanBlobKeys: orphans,
    );
  }

  /// Removes the manga [url] and reports all of its page keys as orphans.
  IndexChange remove(String url) {
    final gone = _byUrl[url];
    return (
      index: LocalIndex._({..._byUrl}..remove(url)),
      orphanBlobKeys: [
        for (final c in gone?.chapters ?? const <LocalChapter>[])
          ...c.pageBlobKeys,
      ],
    );
  }

  /// JSON form; store with `jsonEncode`.
  Map<String, Object?> toJson() => {
    'v': 1,
    'manga': [for (final m in manga) m.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is LocalIndex && listEquals(other.manga, manga);

  @override
  int get hashCode => Object.hashAll(manga);
}
