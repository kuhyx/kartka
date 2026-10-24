import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/common/progress_rules.dart';

void main() {
  group('chaptersReadFrom', () {
    test('floors fractional chapters', () {
      expect(chaptersReadFrom(10.5), 10);
      expect(chaptersReadFrom(10), 10);
    });

    test('null and negative numbers carry no count', () {
      expect(chaptersReadFrom(null), isNull);
      expect(chaptersReadFrom(-1), isNull);
      expect(chaptersReadFrom(double.nan), isNull);
      expect(chaptersReadFrom(double.infinity), isNull);
    });
  });

  group('pushTarget', () {
    test('is the max of local and remote', () {
      expect(pushTarget(local: 5, remote: 3), 5);
      expect(pushTarget(local: 2, remote: 3), 3);
    });

    test('only pushes when local is ahead', () {
      expect(needsPush(local: 5, remote: 3), isTrue);
      expect(needsPush(local: 3, remote: 3), isFalse);
      expect(needsPush(local: 1, remote: 3), isFalse);
    });

    test('skips when already pushed at least that far', () {
      expect(alreadyPushed(local: 5, lastPushed: 5), isTrue);
      expect(alreadyPushed(local: 5, lastPushed: 7), isTrue);
      expect(alreadyPushed(local: 6, lastPushed: 5), isFalse);
      expect(alreadyPushed(local: 6, lastPushed: null), isFalse);
    });
  });

  group('needsPull', () {
    test('pulls when remote is ahead of local', () {
      expect(needsPull(local: 3, remote: 5), isTrue);
      expect(needsPull(local: null, remote: 1), isTrue);
    });

    test('never pulls backwards or zero', () {
      expect(needsPull(local: 5, remote: 5), isFalse);
      expect(needsPull(local: 6, remote: 5), isFalse);
      expect(needsPull(local: null, remote: 0), isFalse);
    });
  });
}
