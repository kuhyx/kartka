import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/models/models.dart';

List<ChapterInfo> _chapters(Iterable<num> numbers) => [
  for (final n in numbers)
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
];

void main() {
  test('no new chapters', () {
    expect(refreshMessage(const RefreshSucceeded([])), 'No new chapters');
  });

  test('three new chapters list every number', () {
    expect(
      refreshMessage(RefreshSucceeded(_chapters([101, 102, 103]))),
      '3 new: ch 101, 102, 103',
    );
  });

  test('more than five list five then +N more', () {
    expect(
      refreshMessage(RefreshSucceeded(_chapters([1, 2, 3, 4, 5, 6, 7]))),
      '7 new: ch 1, 2, 3, 4, 5 +2 more',
    );
    expect(
      refreshMessage(RefreshSucceeded(_chapters([1, 2, 3, 4, 5]))),
      '5 new: ch 1, 2, 3, 4, 5',
    );
  });

  test('decimal numbers keep their fraction; unnumbered show the name', () {
    final added = [
      ..._chapters([10.5]),
      const ChapterInfo(url: '/x', name: 'Extra'),
    ];
    expect(refreshMessage(RefreshSucceeded(added)), '2 new: ch 10.5, Extra');
  });

  test('a failure shows the message with URL secrets redacted', () {
    final message = refreshMessage(
      RefreshFailed(StateError('down https://h.test/x?auth=SECRET')),
    );
    expect(message, startsWith('Refresh failed: '));
    expect(message, contains('https://h.test/x'));
    expect(message, isNot(contains('SECRET')));
  });

  test('stripUrls drops every URL and query string', () {
    expect(
      stripUrls('a https://h.test/x?k=1 b /m/1?c=2 why? end'),
      'a <url> b /m/1?<redacted> why? end',
    );
  });
}
