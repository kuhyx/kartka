import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/core/models/chapter_info.dart';

ChapterInfo ch(String url, [double? n]) =>
    ChapterInfo(url: url, name: url, number: n);

void main() {
  group('readingOrder', () {
    test('sorts numbered chapters ascending, stable on ties', () {
      final order = readingOrder([
        ch('c3', 3),
        ch('c1', 1),
        ch('c2a', 2),
        ch('c2b', 2),
      ]);
      expect(order.map((c) => c.url), ['c1', 'c2a', 'c2b', 'c3']);
    });

    test('any unnumbered chapter: reverses the newest-first source order', () {
      final order = readingOrder([ch('new'), ch('mid', 2), ch('old')]);
      expect(order.map((c) => c.url), ['old', 'mid', 'new']);
    });

    test('empty stays empty', () {
      expect(readingOrder(const []), isEmpty);
    });
  });

  group('firstUnread', () {
    final order = [ch('a', 1), ch('b', 2), ch('c', 3)];

    test('returns the first chapter not in the read set', () {
      expect(firstUnread(order, {'a'})?.url, 'b');
    });

    test('falls back to the first chapter when all are read', () {
      expect(firstUnread(order, {'a', 'b', 'c'})?.url, 'a');
    });

    test('is null for no chapters', () {
      expect(firstUnread(const [], const {}), isNull);
    });
  });

  test('unreadOf keeps reading order and drops read chapters', () {
    final order = [ch('a', 1), ch('b', 2), ch('c', 3)];
    expect(unreadOf(order, {'b'}).map((c) => c.url), ['a', 'c']);
  });

  test('unreadFirst moves unread chapters up, both halves in order', () {
    final shown = [ch('c', 3), ch('b', 2), ch('a', 1)];
    expect(unreadFirst(shown, {'c'}).map((c) => c.url), ['b', 'a', 'c']);
    expect(unreadFirst(shown, const {}).map((c) => c.url), ['c', 'b', 'a']);
  });
}
