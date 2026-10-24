import 'package:kartka/core/models/models.dart';

/// Reading progress and read marks (DOCS-contracts §8).
abstract interface class ProgressRepository {
  /// Furthest position read in [key]; `null` when never opened.
  Stream<ReadingProgress?> watch(MangaKey key);

  /// Records [p]; ignored unless `p.isAheadOf(current)` (never decreases).
  Future<void> record(ReadingProgress p);

  /// Marks one chapter read.
  Future<void> markRead(MangaKey key, String chapterUrl);

  /// Clears an explicit read mark (a `read: false` tombstone, §4).
  Future<void> markUnread(MangaKey key, String chapterUrl);

  /// URLs of chapters read in [key] (progress-derived plus explicit marks).
  Stream<Set<String>> readChapters(MangaKey key);
}
