import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/first_images_probe.dart';

void main() {
  test('fires once, when every watched page failed', () async {
    final seen = <Object>[];
    final probe = FirstImagesProbe([0, 1], seen.add);
    await expectLater(probe.watch(0, Future<int>.error('a')), throwsA('a'));
    expect(seen, isEmpty);
    await expectLater(probe.watch(0, Future<int>.error('a')), throwsA('a'));
    expect(seen, isEmpty, reason: 'the same page twice is one page');
    await expectLater(probe.watch(1, Future<int>.error('b')), throwsA('b'));
    expect(seen, ['b']);
    await expectLater(probe.watch(1, Future<int>.error('c')), throwsA('c'));
    expect(seen, ['b'], reason: 'once only');
  });

  test(
    'a loaded watched page silences it; others are passed through',
    () async {
      final seen = <Object>[];
      final probe = FirstImagesProbe([0, 1], seen.add);
      expect(await probe.watch(7, Future.value(7)), 7);
      expect(await probe.watch(0, Future.value(1)), 1);
      await expectLater(probe.watch(1, Future<int>.error('b')), throwsA('b'));
      expect(seen, isEmpty);
    },
  );

  test('nothing watched never fires', () async {
    final seen = <Object>[];
    final probe = FirstImagesProbe(const [], seen.add);
    await expectLater(probe.watch(0, Future<int>.error('a')), throwsA('a'));
    expect(seen, isEmpty);
  });
}
