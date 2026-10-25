import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';

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

/// Loads the pages of [chapterUrl], downloaded copy first.
///
/// Offline pages are tried first so a downloaded chapter opens without
/// network; only when there are none is [source] asked.
Future<ChapterPages> loadChapterPages({
  required MangaKey key,
  required String chapterUrl,
  required DownloadRepository? downloads,
  MangaSource? source,
}) async {
  final offline = await downloads?.offlinePages(key, chapterUrl);
  if (offline != null && offline.isNotEmpty) {
    return (pages: _sorted(offline), offline: true);
  }
  if (source == null) {
    throw const ReaderLoadException(
      'This chapter is not downloaded and its source is not available.',
    );
  }
  return (pages: _sorted(await source.pages(chapterUrl)), offline: false);
}

/// Loads the chapter the reader advances into, failing on [timeout] and on
/// a chapter with no pages (a blank screen would look like a hang).
Future<ChapterPages> loadNextChapterPages({
  required MangaKey key,
  required String chapterUrl,
  required DownloadRepository? downloads,
  required Duration timeout,
  MangaSource? source,
}) async {
  final loaded = await loadChapterPages(
    key: key,
    chapterUrl: chapterUrl,
    downloads: downloads,
    source: source,
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
