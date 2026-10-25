import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/ui/reader_view_controller.dart';
import 'package:kartka/reader/ui/webtoon_reader_view.dart';

void main() {
  late List<int> items;
  late List<Offset> taps;
  late ReaderViewController controller;

  setUp(() {
    items = [];
    taps = [];
    controller = ReaderViewController();
  });

  Future<void> pump(WidgetTester tester, {int initial = 1}) =>
      tester.pumpWidget(
        MaterialApp(
          home: WebtoonReaderView(
            strip: const ChapterStrip(pageCounts: [6]),
            initialItem: initial,
            slotBuilder: (context, slot) =>
                SizedBox(height: 500, child: Text('$slot')),
            onItemChanged: items.add,
            controller: controller,
            onTap: (p, s) => taps.add(p),
          ),
        ),
      );

  testWidgets('reports the item under the middle as it scrolls', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    expect(find.text('StripSlot.page(0)'), findsOneWidget);
    expect(items, [1]);
    await tester.drag(find.byType(WebtoonReaderView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(items.last, 2);
  });

  testWidgets('step scrolls by most of a screen, jump goes to an item', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    controller.step(1);
    await tester.pumpAndSettle();
    expect(items.last, 2);
    controller.jumpToItem(7);
    await tester.pumpAndSettle();
    expect(items.last, 7);
    expect(find.text('StripSlot.nextChapter()'), findsOneWidget);
    controller.step(-1);
    await tester.pumpAndSettle();
    expect(items.last, lessThan(7));
  });

  testWidgets('taps are forwarded after the double-tap window', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(50, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, [const Offset(50, 60)]);
  });

  testWidgets('a detached controller is a no-op', (tester) async {
    await pump(tester);
    await tester.pumpWidget(const SizedBox());
    controller
      ..step(1)
      ..jumpToItem(3);
    expect(items, [1]);
  });
}
