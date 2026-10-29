import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/updates/data/update_feed.dart';

/// One row of the Updates list (flat, so `ListView.builder` builds lazily).
sealed class UpdateRow {
  const new();
}

/// A day heading: `Today`, `Yesterday` or `yyyy-mm-dd`.
final class DayRow extends UpdateRow {
  /// Heading [label].
  const new(this.label);

  /// The heading text.
  final String label;
}

/// A manga heading (cover and title) above its new chapters.
final class MangaRow extends UpdateRow {
  /// Heading for [entry].
  const new(this.entry);

  /// The library entry.
  final LibraryEntry entry;
}

/// One new chapter.
final class ChapterRow extends UpdateRow {
  /// [chapter] of [entry]; [unread] per the shared read rule.
  const new(this.entry, this.chapter, {required this.unread});

  /// The library entry.
  final LibraryEntry entry;

  /// The chapter.
  final ChapterInfo chapter;

  /// Whether it is still unread.
  final bool unread;
}

/// [events] (newest first) as rows grouped by local day, then by manga in
/// order of each manga's newest event that day. Events of manga no longer
/// in [library] are left out; [marks] decides read state (`isChapterRead`).
List<UpdateRow> groupUpdates(
  List<UpdateEvent> events, {
  required Map<MangaKey, LibraryEntry> library,
  required Map<MangaKey, ReadMarks> marks,
  required DateTime now,
}) {
  final days = <String, Map<MangaKey, List<ChapterInfo>>>{};
  for (final e in events) {
    if (!library.containsKey(e.key)) continue;
    final day = days.putIfAbsent(dayLabel(e.foundAt, now), () => {});
    day.putIfAbsent(e.key, () => []).add(e.chapter);
  }
  return [
    for (final MapEntry(key: label, value: manga) in days.entries) ...[
      DayRow(label),
      for (final MapEntry(:key, value: chapters) in manga.entries) ...[
        MangaRow(library[key]!),
        for (final c in chapters)
          ChapterRow(
            library[key]!,
            c,
            unread: !isChapterRead(c, marks[key] ?? ReadMarks.none),
          ),
      ],
    ],
  ];
}

/// The heading for [at]'s local day, relative to [now]'s.
String dayLabel(DateTime at, DateTime now) {
  final day = _date(at.toLocal());
  final days = _date(now.toLocal()).difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

// Calendar dates as UTC midnights, so a DST change never makes a day 23 h.
DateTime _date(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day);
