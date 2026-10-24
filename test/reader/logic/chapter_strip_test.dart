import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';

void main() {
  const strip = ChapterStrip(pageCount: 3);

  test('pages are framed by a leading and a trailing transition', () {
    expect(strip.itemCount, 5);
    expect(strip.slotAt(0), const StripSlot.previousChapter());
    expect(strip.slotAt(1), const StripSlot.page(0));
    expect(strip.slotAt(3), const StripSlot.page(2));
    expect(strip.slotAt(4), const StripSlot.nextChapter());
    expect(strip.itemForPage(0), 1);
    expect(strip.itemForPage(9), 3);
    expect(strip.itemForPage(-1), 1);
  });

  test('slots outside the strip clamp to the transitions', () {
    expect(strip.slotAt(-1), const StripSlot.previousChapter());
    expect(strip.slotAt(99), const StripSlot.nextChapter());
  });

  test('empty chapter still has both transitions', () {
    const empty = ChapterStrip(pageCount: 0);
    expect(empty.itemCount, 2);
    expect(empty.itemForPage(0), 1);
    expect(empty.slotAt(1), const StripSlot.nextChapter());
  });

  test('slot equality and description', () {
    expect(const StripSlot.page(1), isNot(const StripSlot.page(2)));
    expect(const StripSlot.page(1).hashCode, const StripSlot.page(1).hashCode);
    expect(const StripSlot.page(1).toString(), contains('1'));
    expect(const StripSlot.page(1).isPage, isTrue);
    expect(const StripSlot.nextChapter().isPage, isFalse);
  });
}
