import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';

void main() {
  const strip = ChapterStrip(pageCounts: [3]);

  test('pages are framed by a leading and a trailing slot', () {
    expect(strip.itemCount, 5);
    expect(strip.pageCount, 3);
    expect(strip.slotAt(0), const StripSlot.previousChapter());
    expect(strip.slotAt(1), const StripSlot.page(0));
    expect(strip.slotAt(3), const StripSlot.page(2));
    expect(strip.slotAt(4), const StripSlot.nextChapter());
    expect(strip.itemForPage(0), 1);
    expect(strip.itemForPage(9), 3);
    expect(strip.itemForPage(-1), 1);
  });

  test('slots outside the strip clamp to the edges', () {
    expect(strip.slotAt(-1), const StripSlot.previousChapter());
    expect(strip.slotAt(99), const StripSlot.nextChapter());
  });

  test('chapters follow each other with no slot between them', () {
    const two = ChapterStrip(pageCounts: [3, 2]);
    expect(two.itemCount, 7);
    expect(two.pageCount, 5);
    expect(two.slotAt(3), const StripSlot.page(2));
    expect(two.slotAt(4), const StripSlot.page(0, segment: 1, flat: 3));
    expect(two.slotAt(5), const StripSlot.page(1, segment: 1, flat: 4));
    expect(two.slotAt(6), const StripSlot.nextChapter());
    expect(two.offsetOf(1), 3);
    expect(two.itemForPage(0, segment: 1), 4);
    expect(two.itemForPage(9, segment: 1), 5);
  });

  test('the next chapter lands where the trailing slot was', () {
    const one = ChapterStrip(pageCounts: [3]);
    const two = ChapterStrip(pageCounts: [3, 2]);
    final trailing = one.itemCount - 1;
    expect(one.slotAt(trailing).isPage, isFalse);
    expect(two.slotAt(trailing), const StripSlot.page(0, segment: 1, flat: 3));
  });

  test('empty chapter still has both edges', () {
    const empty = ChapterStrip(pageCounts: [0]);
    expect(empty.itemCount, 2);
    expect(empty.itemForPage(0), 1);
    expect(empty.slotAt(1), const StripSlot.nextChapter());
  });

  test('slot equality and description', () {
    expect(const StripSlot.page(1), isNot(const StripSlot.page(2)));
    expect(
      const StripSlot.page(0),
      isNot(const StripSlot.page(0, segment: 1, flat: 3)),
    );
    expect(const StripSlot.page(1).hashCode, const StripSlot.page(1).hashCode);
    expect(const StripSlot.page(1).toString(), 'StripSlot.page(1)');
    expect(
      const StripSlot.page(1, segment: 2, flat: 7).toString(),
      'StripSlot.page(1, segment: 2)',
    );
    expect(const StripSlot.previousChapter().toString(), contains('previous'));
    expect(const StripSlot.nextChapter().toString(), contains('next'));
    expect(const StripSlot.page(1).isPage, isTrue);
    expect(const StripSlot.page(1).flat, 1);
    expect(const StripSlot.nextChapter().isPage, isFalse);
    expect(const StripSlot.previousChapter().isPreviousChapter, isTrue);
  });
}
