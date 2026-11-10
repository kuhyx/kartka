import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_routes.dart';

import '../support/fakes.dart';
import 'harness.dart';

// Stream reads from the test body run outside fake async, or they stall.
Future<List<String>> _names(WidgetTester tester, Fakes f) async => [
  for (final c in (await tester.runAsync(
    () => f.deps.repos.categories.watch().first,
  ))!)
    c.name,
];

Future<void> _open(WidgetTester tester, Fakes f) async {
  final router = await pumpLibrary(tester, f.deps);
  router.go(libraryCategoriesRoute);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create, rename, reorder by buttons, delete', (tester) async {
    final f = Fakes();
    await _open(tester, f);
    expect(find.bySemanticsLabel('No categories yet'), findsOneWidget);
    for (final name in ['A', 'B']) {
      await tester.tap(find.bySemanticsLabel('Add category'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('New category'), findsOneWidget);
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pumpAndSettle();
    }
    expect(await _names(tester, f), ['A', 'B']);

    await tester.tap(find.bySemanticsLabel('Move down').first);
    await tester.pumpAndSettle();
    expect(await _names(tester, f), ['B', 'A']);
    await tester.tap(find.bySemanticsLabel('Move up').last);
    await tester.pumpAndSettle();
    expect(await _names(tester, f), ['A', 'B']);

    await tester.tap(find.bySemanticsLabel('Rename').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Z');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await _names(tester, f), ['Z', 'B']);

    await tester.tap(find.bySemanticsLabel('Rename').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Delete').first);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Delete "Z"?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete').last);
    await tester.pumpAndSettle();
    expect(await _names(tester, f), ['B']);
    await tester.tap(find.bySemanticsLabel('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(await _names(tester, f), ['B']);
  });

  testWidgets('drag reorders too', (tester) async {
    final f = Fakes();
    for (final (i, n) in ['A', 'B', 'C'].indexed) {
      await f.deps.repos.categories.upsert(
        Category(id: n, name: n, order: i, updatedAt: t0),
      );
    }
    await _open(tester, f);
    final handle = find.byIcon(Icons.drag_handle);
    await tester.drag(handle.first, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect((await _names(tester, f)).first, isNot('A'));
  });
}
