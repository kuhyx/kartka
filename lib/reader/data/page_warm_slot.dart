import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/page_image_warmer.dart';
import 'package:kartka/reader/data/page_list_cache.dart';

/// Fetches the Continue chapter's page list ahead (the progress chapter,
/// else the first unread one) once the manga's details screen has loaded,
/// so tapping Continue opens from [cache] (971debc8).
///
/// Only after [loaded]: beside the details screen's own fetch (the same
/// rate-limited source) it would slow that. Untimed and unreported: no one
/// waits on it, and a WebView timeout only marks the source.
class PageWarmSlot implements MangaDetailSlot {
  /// Warms through [cache]; the repositories are read late (registry).
  const new({
    required this.cache,
    required this.findSource,
    required this.progress,
    required this.downloads,
    this.images,
  });

  /// Where the page list goes.
  final PageListCache cache;

  /// The source with this id, or null.
  final Future<MangaSource?> Function(String sourceId) findSource;

  /// Reading progress, which names the Continue chapter.
  final ProgressRepository? Function() progress;

  /// Downloaded chapters, which need no warm-up.
  final DownloadRepository? Function() downloads;

  /// Where the chapter's first page images go (28fffd0a); none: lists only.
  final PageImageWarmer? images;

  @override
  void opened(MangaKey key) {}

  @override
  void loaded(MangaKey key, {String? firstUnread}) =>
      unawaited(_warm(key, firstUnread));

  Future<void> _warm(MangaKey key, String? firstUnread) async {
    try {
      final saved = await progress()
          ?.watch(key)
          .first
          .timeout(const Duration(seconds: 2));
      final url = saved?.chapterUrl ?? firstUnread;
      if (url == null) return;
      final offline = await downloads()?.offlinePages(key, url);
      if (offline != null && offline.isNotEmpty) return;
      final source = await findSource(splitMangaKey(key).$1);
      if (source == null) return;
      final images = this.images;
      if (images == null) return cache.warm(source, url);
      final pages = await cache.pages(source, url);
      final from = saved?.chapterUrl == url ? saved!.page : 0;
      await images.warm(pages, from: from < pages.length ? from : 0);
    } on Object {
      // Background work: the reader asks again when it opens.
    }
  }

  @override
  Widget build(BuildContext context, MangaKey key, MangaDetails details) =>
      const SizedBox.shrink();
}
