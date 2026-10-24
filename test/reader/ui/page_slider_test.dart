import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/page_slider.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    int page = 2,
    int count = 10,
    bool rtl = false,
  }) async {
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageSlider(
            page: page,
            pageCount: count,
            rightToLeft: rtl,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('shows the 1-based position and jumps on drag', (tester) async {
    final changes = await pump(tester);
    expect(find.text('3 / 10'), findsOneWidget);
    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(changes, isNotEmpty);
    expect(changes.last, inInclusiveRange(4, 5));
  });

  testWidgets('right-to-left flips the track', (tester) async {
    await pump(tester, rtl: true);
    final dir = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byType(Slider),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(dir.textDirection, TextDirection.rtl);
  });

  testWidgets('a one-page chapter shows no slider', (tester) async {
    await pump(tester, page: 0, count: 1);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('1 / 1'), findsOneWidget);
  });
}
