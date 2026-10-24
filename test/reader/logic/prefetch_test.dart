import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/prefetch.dart';

void main() {
  test('next N pages after the current one, clipped to the chapter', () {
    expect(prefetchIndices(current: 0, total: 10, ahead: 3), [1, 2, 3]);
    expect(prefetchIndices(current: 8, total: 10, ahead: 3), [9]);
    expect(prefetchIndices(current: 9, total: 10, ahead: 3), isEmpty);
    expect(prefetchIndices(current: 2, total: 10, ahead: 0), isEmpty);
  });

  test('out-of-range current is clamped', () {
    expect(prefetchIndices(current: -4, total: 3, ahead: 5), [1, 2]);
    expect(prefetchIndices(current: 2, total: 0, ahead: 5), isEmpty);
  });

  test('retain window keeps one page behind and the prefetch ahead', () {
    expect(retainWindow(current: 5, total: 10, ahead: 2), {4, 5, 6, 7});
    expect(retainWindow(current: 0, total: 10, ahead: 1), {0, 1});
    expect(retainWindow(current: 0, total: 0, ahead: 1), isEmpty);
  });
}
