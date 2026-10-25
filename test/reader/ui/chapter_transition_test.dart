import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool forward,
    String? target,
    String? error,
    VoidCallback? onRetry,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChapterTransition(
          forward: forward,
          currentName: 'Ch. 5',
          targetName: target,
          error: error,
          onRetry: onRetry,
        ),
      ),
    ),
  );

  testWidgets('a neighbour on its way shows progress, no button', (
    tester,
  ) async {
    await pump(tester, forward: true, target: 'Ch. 6');
    expect(find.text('Next: Ch. 6'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Finished'), findsNothing);
    await pump(tester, forward: false, target: 'Ch. 4');
    expect(find.text('Previous: Ch. 4'), findsOneWidget);
  });

  testWidgets('a failed neighbour explains and retries from the keyboard', (
    tester,
  ) async {
    var retried = 0;
    await pump(
      tester,
      forward: true,
      target: 'Ch. 6',
      error: 'Timed out after 30 s.',
      onRetry: () => retried++,
    );
    expect(find.text('Could not open Ch. 6'), findsOneWidget);
    expect(find.text('Timed out after 30 s.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('no neighbour says so and has no button', (tester) async {
    await pump(tester, forward: true);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Ch. 5'), findsOneWidget);
    expect(find.text('No next chapter'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await pump(tester, forward: false);
    expect(find.text('Start of'), findsOneWidget);
    expect(find.text('No previous chapter'), findsOneWidget);
  });
}
