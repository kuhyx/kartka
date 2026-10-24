import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:kartka/sources/local/natural_sort.dart';

void main() {
  group('naturalCompare', () {
    test('page2 sorts before page10', () {
      final names = ['page10.jpg', 'page2.jpg', 'page1.jpg'];
      expect(naturalSorted(names), ['page1.jpg', 'page2.jpg', 'page10.jpg']);
    });

    test('compares whole paths so ch1/p2 precedes ch10/p1', () {
      final names = ['ch10/p1.png', 'ch1/p2.png', 'ch2/p1.png'];
      expect(naturalSorted(names), ['ch1/p2.png', 'ch2/p1.png', 'ch10/p1.png']);
    });

    test('is case-insensitive with a deterministic tie-break', () {
      expect(naturalSorted(['B.png', 'a.png', 'A.png']), [
        'A.png',
        'a.png',
        'B.png',
      ]);
    });

    test('leading zeros compare by value, then by raw string', () {
      expect(naturalCompare('p007', 'p7'), isNot(0));
      expect(naturalSorted(['p10', 'p007', 'p8']), ['p007', 'p8', 'p10']);
    });

    test('digit runs longer than int64 do not overflow', () {
      const big = '123456789012345678901234567890';
      expect(naturalCompare('x$big', 'x9'), greaterThan(0));
      expect(naturalCompare('x9', 'x$big'), lessThan(0));
    });

    test('a prefix sorts first', () {
      expect(naturalCompare('page', 'page1'), lessThan(0));
      expect(naturalCompare('page1', 'page'), greaterThan(0));
      expect(naturalCompare('', ''), 0);
    });

    test('digits sort before letters at the same position', () {
      expect(naturalCompare('1a', 'aa'), lessThan(0));
      expect(naturalCompare('aa', '1a'), greaterThan(0));
    });
  });

  group('naturalCompare properties', () {
    Glados2(any.positiveIntOrZero, any.positiveIntOrZero).test(
      'page<a> vs page<b> agrees with integer order',
      (a, b) {
        expect(
          naturalCompare('page$a.jpg', 'page$b.jpg').sign,
          a.compareTo(b).sign,
        );
      },
    );

    Glados2(_names, _names).test('antisymmetric', (a, b) {
      expect(naturalCompare(a, b).sign, -naturalCompare(b, a).sign);
    });

    Glados(_names).test('reflexive and total', (a) {
      expect(naturalCompare(a, a), 0);
    });

    Glados3(_names, _names, _names).test('transitive', (a, b, c) {
      if (naturalCompare(a, b) <= 0 && naturalCompare(b, c) <= 0) {
        expect(naturalCompare(a, c), lessThanOrEqualTo(0));
      }
    });
  });
}

/// Mixed case, zeros and separators: the characters that break naive sorts.
final Generator<String> _names = any.stringOf('aAbB019 ./');
