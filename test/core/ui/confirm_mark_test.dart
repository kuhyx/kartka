import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/confirm_mark.dart';

Future<bool?> _ask(WidgetTester t, String tap) async {
  bool? result;
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () async => result = await confirmMark(
            context,
            icon: Icons.delete_forever,
            semanticLabel: 'Remove it?',
            confirmLabel: 'Remove',
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byIcon(Icons.play_arrow));
  await t.pumpAndSettle();
  expect(find.bySemanticsLabel('Remove it?'), findsOneWidget);
  expect(find.text('Remove it?'), findsNothing);
  if (tap.isEmpty) {
    await t.tapAt(const Offset(4, 4)); // Barrier: dismissed, no answer.
  } else {
    await t.tap(find.bySemanticsLabel(tap));
  }
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('confirm returns true', (t) async {
    expect(await _ask(t, 'Remove'), isTrue);
  });

  testWidgets('cancel returns false', (t) async {
    expect(await _ask(t, 'Cancel'), isFalse);
  });

  testWidgets('dismissing returns false', (t) async {
    expect(await _ask(t, ''), isFalse);
  });
}
