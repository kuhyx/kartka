import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';

import '../../helpers/spoken_icon.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool forward,
    String? target,
    String? error,
    VoidCallback? onRetry,
    bool loading = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChapterTransition(
          forward: forward,
          currentName: 'Ch. 5',
          targetName: target,
          error: error,
          onRetry: onRetry,
          loading: loading,
        ),
      ),
    ),
  );

  testWidgets('a neighbour on its way shows progress, no button', (
    tester,
  ) async {
    await pump(tester, forward: true, target: 'Ch. 6');
    expect(spokenIcon('Next'), findsOneWidget);
    expect(find.text('Ch. 6'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Finished'), findsNothing);
    await pump(tester, forward: false, target: 'Ch. 4');
    expect(spokenIcon('Previous'), findsOneWidget);
    expect(find.text('Ch. 4'), findsOneWidget);
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
    expect(spokenIcon('Could not open'), findsOneWidget);
    expect(find.text('Ch. 6'), findsOneWidget);
    expect(find.text('Timed out after 30 s.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('no neighbour says so and has no button', (tester) async {
    await pump(tester, forward: true);
    expect(find.text('Finished'), findsNothing);
    expect(find.text('Ch. 5'), findsOneWidget);
    expect(spokenIcon('No more chapters'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    await pump(tester, forward: false);
    expect(spokenIcon('Start of, no previous chapter'), findsOneWidget);
    expect(find.text('Ch. 5'), findsOneWidget);
  });

  testWidgets('an unknown next chapter still loads or fails', (tester) async {
    await pump(tester, forward: true, loading: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel('Looking for the next chapter'),
      findsOneWidget,
    );
    expect(spokenIcon('No more chapters'), findsNothing);
    await pump(tester, forward: true, error: 'Offline.', onRetry: () {});
    expect(spokenIcon('Could not open'), findsOneWidget);
    expect(find.text('Ch. 5'), findsNothing);
    expect(find.text('Offline.'), findsOneWidget);
    expect(spokenIcon('Retry'), findsOneWidget);
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(48),
    );
  });
}
