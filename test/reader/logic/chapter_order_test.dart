import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/logic/chapter_order.dart';

ChapterInfo ch(String url, [double? n]) =>
    ChapterInfo(url: url, name: 'Ch $url', number: n);

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
    expect(readingOrder([ch('x', 1), ch('y', 1)]).first.url, 'y');
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
    expect(progressNumber(null, null), 0);
  });
}
