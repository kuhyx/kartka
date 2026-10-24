import 'package:kartka/core/models/models.dart';

/// [chapters] from first to last to read.
///
/// Sources usually list newest first (Tachiyomi convention). The numbers
/// decide when they disagree at the ends; otherwise the convention holds.
List<ChapterInfo> readingOrder(List<ChapterInfo> chapters) {
  if (chapters.length < 2) return List.of(chapters);
  final first = chapters.first.number;
  final last = chapters.last.number;
  final ascending = first != null && last != null && first < last;
  return ascending ? List.of(chapters) : chapters.reversed.toList();
}

/// The chapter being read and its neighbours in reading order.
typedef ChapterNeighbours = ({
  ChapterInfo? current,
  ChapterInfo? previous,
  ChapterInfo? next,
  int? position,
});

/// Neighbours of the chapter at [url] in [chapters] (source order).
ChapterNeighbours neighboursOf(List<ChapterInfo> chapters, String url) {
  final ordered = readingOrder(chapters);
  final i = ordered.indexWhere((c) => c.url == url);
  if (i < 0) return (current: null, previous: null, next: null, position: null);
  return (
    current: ordered[i],
    previous: i > 0 ? ordered[i - 1] : null,
    next: i + 1 < ordered.length ? ordered[i + 1] : null,
    position: i,
  );
}

/// The chapter number to record progress under.
///
/// [ReadingProgress.chapterNumber] is required, but sources do not always
/// number chapters; the 1-based reading position keeps ordering sane then.
double progressNumber(ChapterInfo? chapter, int? position) =>
    chapter?.number ?? ((position ?? -1) + 1).toDouble();
