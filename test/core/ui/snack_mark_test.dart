import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/snack_mark.dart';

void main() {
  Future<BuildContext> pump(WidgetTester t, {bool scaffold = true}) async {
    late BuildContext ctx;
    final probe = Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: scaffold ? Scaffold(body: probe) : probe,
      ),
    );
    return ctx;
  }

  const mark = Icon(Icons.check, semanticLabel: 'Saved');

  testWidgets('a mark shows in a neutral snack bar', (t) async {
    showMark(await pump(t), mark);
    await t.pump();
    expect(find.bySemanticsLabel('Saved'), findsOneWidget);
    expect(t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, isNull);
  });

  testWidgets('an error mark uses the danger hue', (t) async {
    final context = await pump(t);
    showMark(context, mark, error: true);
    await t.pump();
    expect(
      t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      context.statusColors.danger,
    );
  });

  testWidgets('without a messenger it does nothing', (t) async {
    final context = await pump(t, scaffold: false);
    // MaterialApp always provides a messenger; look it up from above it.
    showMark(t.element(find.byType(MaterialApp)), mark);
    await t.pump();
    expect(context.mounted, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });
}
