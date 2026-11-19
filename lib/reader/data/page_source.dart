import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/page_list_cache.dart';

/// Pages of one chapter and where they came from.
typedef ChapterPages = ({List<PageRef> pages, bool offline});

/// Why a chapter could not be opened.
class ReaderLoadException implements Exception {
  /// An error with a user-facing [message].
  const new(this.message);

  /// What went wrong, shown in the reader.
  final String message;

  @override
  String toString() => 'ReaderLoadException: $message';
}

/// The chapter is not downloaded and no source can fetch it (an
/// uninstalled plugin, or an unreachable Suwayomi server listing none): a
/// known state the reader shows, never a `reader.open` report (23686cca).
class ChapterUnavailable extends ReaderLoadException {
  /// The error, with its fixed message.
  const new()
    : super('This chapter is not downloaded and its source is not available.');
}

/// Loads the pages of [chapterUrl], downloaded copy first.
///
/// Offline pages are tried first so a downloaded chapter opens without
/// network; only when there are none is [source] asked, and waited for
/// (a source still being looked up), through [cache] when there is one
/// ([fresh]: Retry, which asks the source even if it is marked).
Future<ChapterPages> loadChapterPages({
  required MangaKey key,
  required String chapterUrl,
  required DownloadRepository? downloads,
  FutureOr<MangaSource?> source,
  PageListCache? cache,
  bool fresh = false,
}) async {
  final offline = await downloads?.offlinePages(key, chapterUrl);
  if (offline != null && offline.isNotEmpty) {
    return (pages: _sorted(offline), offline: true);
  }
  final found = await source;
  if (found == null) throw const ChapterUnavailable();
  final pages = cache == null
      ? await found.pages(chapterUrl)
      : await cache.pages(found, chapterUrl, fresh: fresh);
  return (pages: _sorted(pages), offline: false);
}

/// Loads the chapter the reader advances into, failing on [timeout] and on
/// a chapter with no pages (a blank screen would look like a hang).
Future<ChapterPages> loadNextChapterPages({
  required MangaKey key,
  required String chapterUrl,
  required DownloadRepository? downloads,
  required Duration timeout,
  MangaSource? source,
  PageListCache? cache,
}) async {
  final loaded = await loadChapterPages(
    key: key,
    chapterUrl: chapterUrl,
    downloads: downloads,
    source: source,
    cache: cache,
  ).timeout(timeout);
  if (loaded.pages.isEmpty) {
    throw const ReaderLoadException('The next chapter has no pages.');
  }
  return loaded;
}

/// What to show for a failed advance (still to be redacted).
String advanceFailureMessage(Object error) => switch (error) {
  ReaderLoadException(:final message) => message,
  TimeoutException(:final duration) =>
    'Timed out after ${duration?.inSeconds ?? '?'} s.',
  _ => '$error',
};

List<PageRef> _sorted(List<PageRef> pages) =>
    List.of(pages)..sort((a, b) => a.index.compareTo(b.index));
