import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/fit_pages.dart';

Future<void> _pump(WidgetTester tester, int count) async {
  tester.view
    ..physicalSize = const Size(360, 400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FitPages(
          itemCount: count,
          itemBuilder: (_, i) => Text('item $i'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('one page shows no dots and no counter', (tester) async {
    await _pump(tester, 3);
    expect(find.byKey(const ValueKey<String>('fit-grid-dot-0')), findsNothing);
    expect(find.byKey(const ValueKey<String>('fit-grid-pages')), findsNothing);
    expect(find.text('item 2'), findsOneWidget);
  });

  testWidgets('several pages show dots; a swipe moves the current dot', (
    tester,
  ) async {
    await _pump(tester, 60);
    Color? dot(int i) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey<String>('fit-grid-dot-$i')),
      );
      return (box.decoration! as BoxDecoration).color;
    }

    final first = dot(0);
    expect(dot(1), isNot(first));
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 2000);
    await tester.pumpAndSettle();
    expect(dot(1), first);
    expect(dot(0), isNot(first));
  });

  testWidgets('many pages swap the dots for an N / M counter', (tester) async {
    await _pump(tester, 3000);
    expect(find.byKey(const ValueKey<String>('fit-grid-dot-0')), findsNothing);
    final counter = find.byKey(const ValueKey<String>('fit-grid-pages'));
    expect(tester.widget<Text>(counter).data, startsWith('1 / '));
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 2000);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(counter).data, startsWith('2 / '));
  });
}
