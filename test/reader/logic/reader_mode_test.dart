import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

void main() {
  group('ReaderMode', () {
    test('ids round-trip and unknown ids fall back to null', () {
      for (final m in ReaderMode.values) {
        expect(ReaderMode.fromId(m.id), m);
      }
      expect(ReaderMode.fromId('nope'), isNull);
      expect(ReaderMode.fromId(null), isNull);
    });

    test('axis, direction and paging per mode', () {
      expect(ReaderMode.pagedLtr.axis, Axis.horizontal);
      expect(ReaderMode.pagedRtl.axis, Axis.horizontal);
      expect(ReaderMode.verticalPaged.axis, Axis.vertical);
      expect(ReaderMode.webtoon.axis, Axis.vertical);
      expect(ReaderMode.pagedRtl.reversed, isTrue);
      expect(ReaderMode.pagedLtr.reversed, isFalse);
      expect(ReaderMode.webtoon.isPaged, isFalse);
      expect(ReaderMode.verticalPaged.isPaged, isTrue);
    });

    test('every mode has a label', () {
      expect(ReaderMode.values.map((m) => m.label).toSet(), hasLength(4));
    });
  });
}
