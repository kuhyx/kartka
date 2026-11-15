import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/updates/state/update_rows.dart';
import 'package:kartka/updates/ui/update_groups.dart';

LibraryEntry _m(String id) => LibraryEntry(
  key: mangaKeyOf('s', '/$id'),
  sourceId: 's',
  mangaUrl: '/$id',
  title: id,
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ChapterRow _c(LibraryEntry e, int n, {required bool unread}) => ChapterRow(
  e,
  ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
  unread: unread,
);

void main() {
  test('one group per manga, ordered by its newest day, all days kept', () {
    final a = _m('a');
    final b = _m('b');
    final groups = groupByManga([
      const DayRow('Today'),
      MangaRow(b),
      _c(b, 2, unread: true),
      MangaRow(a),
      _c(a, 9, unread: false),
      const DayRow('Yesterday'),
      MangaRow(a),
      _c(a, 8, unread: true),
      _c(a, 7, unread: true),
    ]);
    expect([for (final g in groups) g.entry.title], ['b', 'a']);
    expect([for (final g in groups) g.unread], [1, 2]);
    expect(
      [
        for (final r in groups[1].rows)
          switch (r) {
            DayRow(:final label) => label,
            ChapterRow(:final chapter) => chapter.name,
            MangaRow() => 'manga',
          },
      ],
      ['Today', 'Ch. 9', 'Yesterday', 'Ch. 8', 'Ch. 7'],
    );
  });

  test('no rows, no groups', () => expect(groupByManga([]), isEmpty));
}
