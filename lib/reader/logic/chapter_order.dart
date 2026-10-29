import 'package:kartka/core/models/models.dart';

/// [chapters] from first to last to read.
///
/// Sources usually list newest first (Tachiyomi convention); the numbered
/// chapters decide the direction (an unnumbered entry at an end never flips
/// it). Numbered chapters are then sorted by number, ties in source order
/// (several groups can release the same number), and unnumbered ones keep
/// the slot they had in the source list.
List<ChapterInfo> readingOrder(List<ChapterInfo> chapters) {
  if (chapters.length < 2) return List.of(chapters);
  final indexed = chapters.indexed.toList();
  final oriented = _ascending(chapters) ? indexed : indexed.reversed.toList();
  final numbered =
      [
        for (final e in oriented)
          if (e.$2.number != null) e,
      ]..sort((a, b) {
        final byNumber = a.$2.number!.compareTo(b.$2.number!);
        return byNumber != 0 ? byNumber : a.$1.compareTo(b.$1);
      });
  final it = numbered.iterator;
  return [
    for (final e in oriented)
      if (e.$2.number == null) e.$2 else (it..moveNext()).current.$2,
  ];
}

/// Whether the numbered chapters of [chapters] climb through the list
/// (oldest first); otherwise, and when they never move, newest first.
bool _ascending(List<ChapterInfo> chapters) {
  var votes = 0;
  double? before;
  for (final c in chapters) {
    final n = c.number;
    if (n == null) continue;
    if (before != null) votes += n.compareTo(before);
    before = n;
  }
  return votes > 0;
}

/// The chapter being read and its neighbours in reading order.
typedef ChapterNeighbours = ({
  ChapterInfo? current,
  ChapterInfo? previous,
  ChapterInfo? next,
  int? position,
});

/// Neighbours of the chapter at [url] in [chapters] (source order).
///
/// A neighbour is the nearest chapter with a different number, so another
/// group's copy of the current number is skipped; among several groups
/// holding that number the current chapter's scanlator wins, else the first
/// in source order. Unnumbered chapters are neighbours by position.
ChapterNeighbours neighboursOf(List<ChapterInfo> chapters, String url) {
  final ordered = readingOrder(chapters);
  final i = ordered.indexWhere((c) => c.url == url);
  if (i < 0) return (current: null, previous: null, next: null, position: null);
  final current = ordered[i];
  return (
    current: current,
    previous: _step(ordered, i, -1),
    next: _step(ordered, i, 1),
    position: i,
  );
}

/// The neighbour of `ordered[i]` in direction [dir] (1 or -1), or null.
ChapterInfo? _step(List<ChapterInfo> ordered, int i, int dir) {
  final current = ordered[i];
  var k = i + dir;
  while (current.number != null &&
      k >= 0 &&
      k < ordered.length &&
      ordered[k].number == current.number) {
    k += dir;
  }
  if (k < 0 || k >= ordered.length) return null;
  final first = ordered[k];
  final number = first.number;
  if (number == null) return first;
  // The run of this number, from its first (source order) entry on.
  final run = [
    for (final c in ordered)
      if (c.number == number) c,
  ];
  final group = current.scanlator;
  return run.firstWhere(
    (c) => group != null && c.scanlator == group,
    orElse: () => run.first,
  );
}

/// The chapter number to record progress under, or null when unknown.
///
/// [ReadingProgress.chapterNumber] is required, but sources do not always
/// number chapters; the 1-based reading position keeps ordering sane then.
/// A chapter missing from the list (offline, list failed) has no number, and
/// the reader must not record it: a guess could sort behind real progress.
double? progressNumber(ChapterInfo? chapter, int? position) {
  final number = chapter?.number;
  if (number != null) return number;
  return position == null ? null : (position + 1).toDouble();
}
