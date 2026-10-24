import 'package:kartka/core/models/models.dart';

/// Offline chapter downloads (DOCS-contracts §8; owner: downloads part).
abstract interface class DownloadRepository {
  /// Queues [chapter] of [key] for download.
  Future<void> enqueue(MangaKey key, ChapterInfo chapter);

  /// Download state of one chapter; [DownloadState.none] when not queued.
  Stream<DownloadState> watch(MangaKey key, String chapterUrl);

  /// The stored pages (`kartka-blob://` URLs, §11), or `null` when the
  /// chapter is not fully downloaded.
  Future<List<PageRef>?> offlinePages(MangaKey key, String chapterUrl);
}
