import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:kartka/browse/state/combine_latest.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';

const _marksEq = MapEquality<String, bool>();

/// Everything that decides whether a chapter of one manga is read.
@immutable
class ReadMarks {
  /// Creates marks; [marks] maps chapterUrl to its explicit mark (`false` =
  /// an explicit unread tombstone), [progressNumber] is the furthest chapter
  /// number reached (null when never read), [progress] the position in it.
  const new({required this.marks, this.progressNumber, this.progress});

  /// No marks and no progress: nothing is read.
  static const none = ReadMarks(marks: {});

  /// Explicit per-chapter marks (`ProgressRepository.readMarks`).
  final Map<String, bool> marks;

  /// `ReadingProgress.chapterNumber`, or null without progress.
  final double? progressNumber;

  /// The reading position, or null without progress.
  final ReadingProgress? progress;

  @override
  bool operator ==(Object other) =>
      other is ReadMarks &&
      other.progressNumber == progressNumber &&
      other.progress == progress &&
      _marksEq.equals(other.marks, marks);

  @override
  int get hashCode =>
      Object.hash(_marksEq.hash(marks), progressNumber, progress);
}

/// THE read rule (tracker pull-forward and imports move progress without
/// marking each chapter): an explicit mark decides; otherwise a numbered
/// chapter below the progress chapter number is read. The progress chapter
/// itself is only being read: opening it must not finish it, and every
/// path that does finish it (last page, tracker, import) marks it.
bool isChapterRead(ChapterInfo chapter, ReadMarks m) {
  final explicit = m.marks[chapter.url];
  if (explicit != null) return explicit;
  final n = chapter.number;
  final p = m.progressNumber;
  return n != null && p != null && n < p;
}

/// `"<pages read>/<pages>"` for the chapter being read, when its page count
/// is known and it has no explicit mark; null for every other chapter. A
/// chapter marked unread after finishing keeps its last-page progress
/// (progress never decreases), so it shows nothing rather than "30/30".
String? pagesRead(ChapterInfo chapter, ReadMarks m) {
  final p = m.progress;
  final count = p?.pageCount;
  if (p == null || count == null || p.chapterUrl != chapter.url) return null;
  if (m.marks.containsKey(chapter.url) || isChapterRead(chapter, m)) {
    return null;
  }
  return '${p.page + 1}/$count';
}

/// Urls of the read chapters among [chapters].
Set<String> readUrls(List<ChapterInfo> chapters, ReadMarks m) => {
  for (final c in chapters)
    if (isChapterRead(c, m)) c.url,
};

/// How many of [chapters] are unread.
int unreadCount(List<ChapterInfo> chapters, ReadMarks m) =>
    chapters.where((c) => !isChapterRead(c, m)).length;

/// Live [ReadMarks] of [key]: explicit marks plus the progress number.
Stream<ReadMarks> watchReadMarks(ProgressRepository progress, MangaKey key) =>
    combineLatest2(
      progress.readMarks(key),
      progress.watch(key),
      (marks, p) => ReadMarks(
        marks: marks,
        progressNumber: p?.chapterNumber,
        progress: p,
      ),
    );
