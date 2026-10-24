import 'package:glados/glados.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';

/// Chapter i has url '/c<i>' and number i/2, or no number when i is 0 mod 5.
ChapterInfo _ch(int i) =>
    ChapterInfo(url: '/c$i', name: 'c$i', number: i % 5 == 0 ? null : i / 2);

extension on Any {
  Generator<ReadMarks> get marks => combine3(
    any.list(intInRange(0, 12)),
    any.list(intInRange(0, 12)),
    any.intInRange(-1, 12),
    (read, unread, p) => ReadMarks(
      // Later writes win, as in the LWW mark table.
      marks: {
        for (final i in unread) '/c$i': false,
        for (final i in read) '/c$i': true,
      },
      progressNumber: p < 0 ? null : p / 2,
    ),
  );
}

void main() {
  final chapters = [for (var i = 0; i < 12; i++) _ch(i)];

  Glados(any.marks).test('explicit read always counts as read', (m) {
    for (final c in chapters) {
      if (m.marks[c.url] ?? false) expect(isChapterRead(c, m), isTrue);
    }
  });

  Glados(any.marks).test('explicit unread wins over progress', (m) {
    for (final c in chapters) {
      if (m.marks[c.url] == false) expect(isChapterRead(c, m), isFalse);
    }
  });

  Glados(any.marks).test('unmarked: read iff numbered and <= progress', (m) {
    for (final c in chapters) {
      if (m.marks.containsKey(c.url)) continue;
      final p = m.progressNumber;
      final expected = c.number != null && p != null && c.number! <= p;
      expect(isChapterRead(c, m), expected);
    }
  });

  Glados(any.marks).test('readUrls and unreadCount partition chapters', (m) {
    final read = readUrls(chapters, m);
    expect(read.length + unreadCount(chapters, m), chapters.length);
    for (final c in chapters) {
      expect(read.contains(c.url), isChapterRead(c, m));
    }
  });

  test('ReadMarks.none reads nothing and has value equality', () {
    expect(readUrls(chapters, ReadMarks.none), isEmpty);
    const a = ReadMarks(marks: {'/a': true}, progressNumber: 1);
    const b = ReadMarks(marks: {'/a': true}, progressNumber: 1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == ReadMarks.none, isFalse);
  });
}
