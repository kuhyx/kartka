import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/spoken_label.dart';

void main() {
  testWidgets('a spoken label is never painted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SpokenLabel(semanticLabel: 'Retry', child: Icon(Icons.refresh)),
      ),
    );
    expect(find.bySemanticsLabel('Retry'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('an empty mark is a faded glyph with a spoken name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyMark(icon: Icons.inbox, semanticLabel: 'Nothing here'),
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox), findsOneWidget);
    expect(find.bySemanticsLabel('Nothing here'), findsOneWidget);
    expect(find.text('Nothing here'), findsNothing);
  });
}
