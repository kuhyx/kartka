import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/paged_reader_view.dart';
import 'package:kartka/reader/ui/reader_view_controller.dart';
import 'package:kartka/reader/ui/zoomable_page.dart';

void main() {
  late List<int> items;
  late List<(Offset, Size)> taps;
  late ReaderViewController controller;

  setUp(() {
    items = [];
    taps = [];
    controller = ReaderViewController();
  });

  Future<void> pump(WidgetTester tester, ReaderMode mode) => tester.pumpWidget(
    MaterialApp(
      home: PagedReaderView(
        mode: mode,
        strip: const ChapterStrip(pageCount: 3),
        initialItem: 1,
        slotBuilder: (context, slot) => Text('$slot'),
        onItemChanged: items.add,
        controller: controller,
        onTap: (p, s) => taps.add((p, s)),
      ),
    ),
  );

  PageView pager(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView));

  testWidgets('starts at the initial item; swiping LTR advances', (
    tester,
  ) async {
    await pump(tester, ReaderMode.pagedLtr);
    expect(find.text('StripSlot.page(0)'), findsOneWidget);
    expect(pager(tester).reverse, isFalse);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(items, [2]);
  });

  testWidgets('RTL reverses and vertical changes the axis', (tester) async {
    await pump(tester, ReaderMode.pagedRtl);
    expect(pager(tester).reverse, isTrue);
    await pump(tester, ReaderMode.verticalPaged);
    expect(pager(tester).scrollDirection, Axis.vertical);
  });

  testWidgets('controller steps and jumps, clamped to the strip', (
    tester,
  ) async {
    await pump(tester, ReaderMode.pagedLtr);
    controller.step(1);
    await tester.pumpAndSettle();
    expect(items, [2]);
    controller.jumpToItem(99);
    await tester.pumpAndSettle();
    expect(items, [2, 4]);
    expect(find.text('StripSlot.nextChapter()'), findsOneWidget);
  });

  testWidgets('taps on pages and transitions report the viewport size', (
    tester,
  ) async {
    await pump(tester, ReaderMode.pagedLtr);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));
    controller.jumpToItem(0);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(taps.map((t) => t.$1), [const Offset(10, 10), const Offset(20, 20)]);
    expect(taps.first.$2, const Size(800, 600));
  });

  testWidgets('a zoomed page locks swiping until zoomed out', (tester) async {
    await pump(tester, ReaderMode.pagedLtr);
    tester.widget<ZoomablePage>(find.byType(ZoomablePage)).onZoomChanged!(true);
    await tester.pump();
    expect(pager(tester).physics, isA<NeverScrollableScrollPhysics>());
    tester.widget<ZoomablePage>(find.byType(ZoomablePage)).onZoomChanged!(
      false,
    );
    await tester.pump();
    expect(pager(tester).physics, isA<PageScrollPhysics>());
  });

  testWidgets('a detached controller is a no-op', (tester) async {
    await pump(tester, ReaderMode.pagedLtr);
    await tester.pumpWidget(const SizedBox());
    controller
      ..step(1)
      ..jumpToItem(2);
    expect(items, isEmpty);
  });
}
