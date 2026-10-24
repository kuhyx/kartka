import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool forward,
    String? target,
    VoidCallback? onGo,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChapterTransition(
          forward: forward,
          currentName: 'Ch. 5',
          targetName: target,
          onGo: onGo,
        ),
      ),
    ),
  );

  testWidgets('forward: finished current, offers next', (tester) async {
    var went = 0;
    await pump(tester, forward: true, target: 'Ch. 6', onGo: () => went++);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Ch. 5'), findsOneWidget);
    expect(find.text('Next: Ch. 6'), findsOneWidget);
    await tester.tap(find.text('Next: Ch. 6'));
    expect(went, 1);
  });

  testWidgets('the button is keyboard reachable', (tester) async {
    var went = 0;
    await pump(tester, forward: false, target: 'Ch. 4', onGo: () => went++);
    expect(find.text('Previous: Ch. 4'), findsOneWidget);
    expect(find.text('Start of'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(went, 1);
  });

  testWidgets('no neighbour says so and has no button', (tester) async {
    await pump(tester, forward: true);
    expect(find.text('No next chapter'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await pump(tester, forward: false);
    expect(find.text('No previous chapter'), findsOneWidget);
  });
}
