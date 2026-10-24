import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/webtoon_position.dart';

void main() {
  WebtoonItemPosition visible(int i, double l, double t) =>
      (index: i, leading: l, trailing: t);

  test('the item under the viewport middle is current', () {
    expect(
      currentWebtoonItem([visible(1, -0.2, 0.3), visible(2, 0.3, 1.2)]),
      2,
    );
    expect(
      currentWebtoonItem([visible(2, 0.3, 1.2), visible(1, -0.6, 0.3)]),
      2,
    );
  });

  test('the last item wins once its bottom is on screen', () {
    expect(
      currentWebtoonItem([visible(3, -0.5, 0.6), visible(4, 0.6, 0.9)]),
      4,
    );
  });

  test('a gap at the middle falls back to the first visible item', () {
    expect(currentWebtoonItem([visible(5, 0.6, 1.4)]), 5);
    expect(currentWebtoonItem(const []), isNull);
  });
}
