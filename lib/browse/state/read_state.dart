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
  /// number reached (null when never read).
  const new({required this.marks, this.progressNumber});

  /// No marks and no progress: nothing is read.
  static const none = ReadMarks(marks: {});

  /// Explicit per-chapter marks (`ProgressRepository.readMarks`).
  final Map<String, bool> marks;

  /// `ReadingProgress.chapterNumber`, or null without progress.
  final double? progressNumber;

  @override
  bool operator ==(Object other) =>
      other is ReadMarks &&
      other.progressNumber == progressNumber &&
      _marksEq.equals(other.marks, marks);

  @override
  int get hashCode => Object.hash(_marksEq.hash(marks), progressNumber);
}

/// THE read rule (tracker pull-forward and imports move progress without
/// marking each chapter): an explicit mark decides; otherwise a numbered
/// chapter at or below the progress chapter number is read.
bool isChapterRead(ChapterInfo chapter, ReadMarks m) {
  final explicit = m.marks[chapter.url];
  if (explicit != null) return explicit;
  final n = chapter.number;
  final p = m.progressNumber;
  return n != null && p != null && n <= p;
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
      (marks, p) => ReadMarks(marks: marks, progressNumber: p?.chapterNumber),
    );
