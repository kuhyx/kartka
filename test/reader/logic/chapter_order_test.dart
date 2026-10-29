import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/logic/chapter_order.dart';

ChapterInfo ch(String url, [double? n, String? group]) =>
    ChapterInfo(url: url, name: 'Ch $url', number: n, scanlator: group);

String? nextUrl(List<ChapterInfo> l, String url) =>
    neighboursOf(l, url).next?.url;

String? prevUrl(List<ChapterInfo> l, String url) =>
    neighboursOf(l, url).previous?.url;

void main() {
  test('newest-first source lists are read oldest first', () {
    final list = [ch('c3', 3), ch('c2', 2), ch('c1', 1)];
    expect(readingOrder(list).map((c) => c.url), ['c1', 'c2', 'c3']);
    final n = neighboursOf(list, 'c2');
    expect(n.previous?.url, 'c1');
    expect(n.next?.url, 'c3');
    expect(n.current?.url, 'c2');
    expect(n.position, 1);
  });

  test('oldest-first lists keep their order', () {
    final list = [ch('a', 1), ch('b', 2)];
    expect(readingOrder(list).map((c) => c.url), ['a', 'b']);
    expect(neighboursOf(list, 'a').previous, isNull);
    expect(neighboursOf(list, 'b').next, isNull);
  });

  test('unnumbered lists follow the newest-first convention', () {
    final list = [ch('new'), ch('old')];
    expect(readingOrder(list).map((c) => c.url), ['old', 'new']);
    expect(readingOrder([ch('x', 1), ch('y', 1)]).first.url, 'x');
    expect(readingOrder(const []), isEmpty);
  });

  test('an unknown chapter has no neighbours', () {
    final n = neighboursOf([ch('a', 1)], 'zzz');
    expect(n.current, isNull);
    expect(n.previous, isNull);
    expect(n.next, isNull);
    expect(n.position, isNull);
  });

  test('progress number falls back to the reading position', () {
    expect(progressNumber(ch('a', 4.5), 0), 4.5);
    expect(progressNumber(ch('a'), 2), 3);
    expect(progressNumber(null, null), isNull);
  });

  group('several scanlation groups', () {
    // Newest first: Ch.12, then Ch.11 by two groups, then Ch.10.
    final list = [
      ch('mm12', 12, 'MM'),
      ch('mm11', 11, 'MM'),
      ch('hy11', 11, 'Hyakuro'),
      ch('mm10', 10, 'MM'),
    ];

    test('next skips a same-number chapter of another group', () {
      expect(nextUrl(list, 'mm11'), 'mm12');
      expect(nextUrl(list, 'hy11'), 'mm12');
      expect(prevUrl(list, 'mm11'), 'mm10');
      expect(prevUrl(list, 'hy11'), 'mm10');
    });

    test('a number held by several groups prefers the current group', () {
      final l = [
        ch('a12', 12, 'A'),
        ch('b12', 12, 'B'),
        ch('a11', 11, 'A'),
        ch('b11', 11, 'B'),
        ch('b10', 10, 'B'),
        ch('a10', 10, 'A'),
      ];
      expect(nextUrl(l, 'b10'), 'b11');
      expect(nextUrl(l, 'a10'), 'a11');
      expect(nextUrl(l, 'b11'), 'b12');
      expect(prevUrl(l, 'a12'), 'a11');
      expect(prevUrl(l, 'b12'), 'b11');
    });

    test('another group is used when the current one lacks the number', () {
      final l = [ch('c12', 12, 'C'), ch('d12', 12, 'D'), ch('a11', 11, 'A')];
      expect(nextUrl(l, 'a11'), 'c12');
      expect(prevUrl(l, 'c12'), 'a11');
    });

    test('ties keep source order in reading order', () {
      final l = [ch('x', 5), ch('y', 5), ch('z', 4)];
      expect(readingOrder(l).map((c) => c.url), ['z', 'x', 'y']);
    });
  });

  group('unnumbered chapters', () {
    test('an unnumbered end entry does not flip the direction', () {
      final newestFirst = [ch('extra'), ch('c3', 3), ch('c2', 2), ch('c1', 1)];
      expect(readingOrder(newestFirst).map((c) => c.url), [
        'c1',
        'c2',
        'c3',
        'extra',
      ]);
      final oldestFirst = [ch('c1', 1), ch('c2', 2), ch('c3', 3), ch('extra')];
      expect(readingOrder(oldestFirst).map((c) => c.url), [
        'c1',
        'c2',
        'c3',
        'extra',
      ]);
    });

    test('an unnumbered chapter keeps its place between neighbours', () {
      final l = [ch('c3', 3), ch('omake'), ch('c2', 2), ch('c1', 1)];
      expect(readingOrder(l).map((c) => c.url), ['c1', 'c2', 'omake', 'c3']);
      expect(nextUrl(l, 'c2'), 'omake');
      expect(nextUrl(l, 'omake'), 'c3');
      expect(prevUrl(l, 'c3'), 'omake');
    });

    test('numbers still sort around an unnumbered chapter', () {
      final l = [ch('c1', 1), ch('c2', 2), ch('mid'), ch('c4', 4), ch('c3', 3)];
      expect(readingOrder(l).map((c) => c.url), [
        'c1',
        'c2',
        'mid',
        'c3',
        'c4',
      ]);
    });
  });

  group('properties', () {
    // A newest-first source list: numbers 1..n, each held by 1-3 groups.
    List<ChapterInfo> listFrom(List<int> copies) {
      final out = <ChapterInfo>[];
      for (var n = 0; n < copies.length; n++) {
        for (var g = 0; g <= copies[n] % 3; g++) {
          out.add(ch('n${n + 1}g$g', n + 1.0, 'g$g'));
        }
      }
      return out.reversed.toList();
    }

    Glados(any.list(any.intInRange(0, 9))).test(
      'walking next from the first chapter visits each number once, upwards',
      (copies) {
        final l = listFrom(copies);
        if (l.isEmpty) return;
        var cur = readingOrder(l).first;
        final seen = <double>[cur.number!];
        for (var i = 0; i < l.length; i++) {
          final next = neighboursOf(l, cur.url).next;
          if (next == null) break;
          expect(next.number, greaterThan(cur.number!));
          seen.add(next.number!);
          cur = next;
        }
        expect(seen, [for (var n = 1; n <= copies.length; n++) n.toDouble()]);
        expect(neighboursOf(l, cur.url).next, isNull);
      },
    );

    Glados(any.list(any.intInRange(0, 9))).test(
      'next and previous stay in the current group when it has the number',
      (copies) {
        final l = listFrom(copies);
        for (final c in l) {
          final n = neighboursOf(l, c.url);
          for (final other in [n.next, n.previous]) {
            if (other == null) continue;
            final sameGroupHasIt = l.any(
              (x) => x.number == other.number && x.scanlator == c.scanlator,
            );
            if (sameGroupHasIt) expect(other.scanlator, c.scanlator);
          }
        }
      },
    );
  });
}
