import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/section_mark.dart';

void main() {
  testWidgets('a section mark is a glyph in the header gutter', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionMark(Icons.link, semanticLabel: 'Repositories'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Repositories'), findsOneWidget);
    expect(find.text('Repositories'), findsNothing);
    expect(
      t.getTopLeft(find.byIcon(Icons.link)).dx,
      greaterThanOrEqualTo(AppSpacing.md),
    );
  });
}
