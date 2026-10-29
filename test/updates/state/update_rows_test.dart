import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/updates/data/update_feed.dart';
import 'package:kartka/updates/state/update_rows.dart';

ChapterInfo _ch(int n) =>
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble());

LibraryEntry _entry(String url) => LibraryEntry(
  key: mangaKeyOf('mangadex', url),
  sourceId: 'mangadex',
  mangaUrl: url,
  title: 'Title $url',
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

String _describe(UpdateRow r) => switch (r) {
  DayRow(:final label) => 'day $label',
  MangaRow(:final entry) => 'manga ${entry.mangaUrl}',
  ChapterRow(:final chapter, :final unread) =>
    '  ${chapter.url}${unread ? ' •' : ''}',
};

void main() {
  // Local noon, so "today" does not depend on the test machine's zone.
  final now = DateTime(2026, 10, 29, 12);
  final a = _entry('/a');
  final b = _entry('/b');

  UpdateEvent ev(LibraryEntry e, int n, DateTime at) =>
      UpdateEvent(key: e.key, chapter: _ch(n), foundAt: at.toUtc());

  test('day labels', () {
    expect(dayLabel(DateTime(2026, 10, 29, 0, 1), now), 'Today');
    expect(dayLabel(DateTime(2026, 10, 28, 23, 59), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 3, 5, 8), now), '2026-03-05');
  });

  test('grouped by day, then manga; unread marked; strangers hidden', () {
    final events = [
      ev(a, 5, DateTime(2026, 10, 29, 11)),
      ev(b, 9, DateTime(2026, 10, 29, 10)),
      ev(a, 4, DateTime(2026, 10, 29, 9)),
      ev(_entry('/gone'), 1, DateTime(2026, 10, 29, 9)),
      ev(a, 3, DateTime(2026, 10, 27, 9)),
    ];
    final rows = groupUpdates(
      events,
      library: {a.key: a, b.key: b},
      marks: {
        a.key: const ReadMarks(marks: {'/c/5': true}),
      },
      now: now,
    );
    expect(rows.map(_describe), [
      'day Today',
      'manga /a',
      '  /c/5',
      '  /c/4 •',
      'manga /b',
      '  /c/9 •',
      'day 2026-10-27',
      'manga /a',
      '  /c/3 •',
    ]);
    final chapter = rows.whereType<ChapterRow>().first;
    expect(chapter.entry, a);
  });

  test('nothing to show is an empty list', () {
    expect(
      groupUpdates(const [], library: const {}, marks: const {}, now: now),
      isEmpty,
    );
  });
}
