import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';

import '../support/fakes.dart';
import 'harness.dart';

const _a = 'mangadex|/manga/aaa';
const _b = 'mangadex|/manga/bbb';

/// Both entries start in "Default"; [reading] puts Berserk in "Reading".
Future<Fakes> _seed({bool reading = false}) async {
  final f = Fakes();
  final lib = f.deps.repos.library;
  await lib.upsert(entry('/manga/aaa', title: 'Akira', addedDays: 1));
  await lib.upsert(entry('/manga/bbb', title: 'Berserk'));
  await f.deps.repos.categories.upsert(
    Category(id: 'x', name: 'Reading', order: 0, updatedAt: t0),
  );
  if (reading) await f.deps.repos.categories.setMembership(_b, 'x', true);
  return f;
}

void main() {
  testWidgets('grid shows entries, unread badge, empty state', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    expect(find.text('Akira'), findsOneWidget);
    expect(find.text('Berserk'), findsOneWidget);
    f.unread.emit(_a, 7);
    await tester.pump();
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
    await f.deps.repos.library.remove(_a);
    await f.deps.repos.library.remove(_b);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Your library is empty'), findsOneWidget);
  });

  testWidgets('unavailable source badge; tap still opens detail', (
    tester,
  ) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    final badge = find.bySemanticsLabel(RegExp('Source unavailable'));
    expect(badge, findsNothing);
    f.sources.emit(['suwayomi:1']);
    await tester.pump();
    await tester.pump();
    expect(badge, findsNWidgets(2));
    await tester.tap(find.text('Akira'));
    await tester.pumpAndSettle();
    expect(find.text('detail mangadex /manga/aaa'), findsOneWidget);
  });

  testWidgets('category tabs filter the grid', (tester) async {
    await pumpLibrary(tester, (await _seed(reading: true)).deps);
    expect(find.text('Berserk'), findsNothing);
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    expect(find.text('Berserk'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Default')));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsOneWidget);
    expect(find.text('Berserk'), findsNothing);
  });

  testWidgets('tap opens the detail route with the url as one segment', (
    tester,
  ) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.text('Akira'));
    await tester.pumpAndSettle();
    expect(find.text('detail mangadex /manga/aaa'), findsOneWidget);
  });

  testWidgets('search narrows by title and closing clears it', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ber');
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
  });

  testWidgets('keyboard focus reaches a cover and Enter opens it', (
    tester,
  ) async {
    await pumpLibrary(tester, (await _seed()).deps);
    Focus.of(tester.element(find.text('Akira'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('detail mangadex /manga/aaa'), findsOneWidget);
  });

  testWidgets('sort and filter sheet', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    await tester.tap(find.bySemanticsLabel('Sort and filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Date added'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final akira = tester.getTopLeft(find.text('Akira'));
    final berserk = tester.getTopLeft(find.text('Berserk'));
    expect(akira.dx, lessThan(berserk.dx));
    await tester.tap(find.bySemanticsLabel('Sort and filter'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Filter'), findsOneWidget);
    expect(find.bySemanticsLabel('Sort by'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Descending'));
    await tester.tap(find.bySemanticsLabel('Downloaded'));
    await tester.tap(find.bySemanticsLabel('Unread'));
    await tester.tap(find.bySemanticsLabel('Tracked'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Title'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('No matches'), findsOneWidget);
  });

  testWidgets('long-press selects; remove then undo', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.longPress(find.text('Akira'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1 selected'), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 selected'), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    expect(find.bySemanticsLabel('Removed 1 from library'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsOneWidget);
    expect(find.bySemanticsLabel('Undo'), findsNothing);
  });

  testWidgets('keyboard: Select, select all, Escape exits', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.bySemanticsLabel('Select'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Select all'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 selected'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Library'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Exit selection'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Library'), findsOneWidget);
  });

  testWidgets('set categories for the selection', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    await tester.longPress(find.text('Akira'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Reading'));
    await tester.tap(find.bySemanticsLabel('Apply'));
    await tester.pumpAndSettle();
    final m = (await tester.runAsync(
      () => f.deps.repos.categories.watchMembership().first,
    ))!;
    expect(m[_a], {'x'});
    // Akira left "Default": the selection ends so nothing hidden stays picked.
    expect(find.text('Akira'), findsNothing);
    expect(find.bySemanticsLabel('Library'), findsOneWidget);
    await tester.longPress(find.text('Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1 selected'), findsOneWidget);
  });

  testWidgets('edit categories opens the categories screen', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.bySemanticsLabel('Edit categories'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Categories'), findsOneWidget);
  });
}
