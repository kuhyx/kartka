import 'package:kartka/core/models/models.dart';
import 'package:kartka/updates/state/update_rows.dart';

/// One manga's new chapters over all days, for one grid tile and its sheet.
class UpdateGroup {
  /// Group of [entry]; [rows] are `DayRow`s each followed by its chapters.
  const new(this.entry, this.rows, this.unread);

  /// The library entry.
  final LibraryEntry entry;

  /// Day headings and chapters, newest day first.
  final List<UpdateRow> rows;

  /// Number of chapters still unread.
  final int unread;
}

/// [rows] (days newest first, see `groupUpdates`) regrouped per manga, in
/// order of each manga's newest day, so each manga gets one tile.
List<UpdateGroup> groupByManga(List<UpdateRow> rows) {
  final byKey = <MangaKey, (LibraryEntry, List<UpdateRow>)>{};
  DayRow? day;
  for (final row in rows) {
    switch (row) {
      case DayRow():
        day = row;
      case MangaRow(:final entry):
        final rows = byKey.putIfAbsent(entry.key, () => (entry, []));
        rows.$2.add(day!);
      case ChapterRow(:final entry):
        byKey[entry.key]!.$2.add(row);
    }
  }
  return [
    for (final (entry, rows) in byKey.values)
      UpdateGroup(
        entry,
        rows,
        rows.whereType<ChapterRow>().where((c) => c.unread).length,
      ),
  ];
}
