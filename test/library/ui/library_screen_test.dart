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
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('unavailable source badge; tap still opens detail', (
    tester,
  ) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    expect(find.byTooltip('Source unavailable'), findsNothing);
    f.sources.emit(['suwayomi:1']);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Source unavailable'), findsNWidgets(2));
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
    await tester.tap(find.text('Default'));
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
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ber');
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsOneWidget);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Search'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Sort and filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date added'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final akira = tester.getTopLeft(find.text('Akira'));
    final berserk = tester.getTopLeft(find.text('Berserk'));
    expect(akira.dx, lessThan(berserk.dx));
    await tester.tap(find.byTooltip('Sort and filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descending'));
    await tester.tap(find.text('Downloaded'));
    await tester.tap(find.text('Unread'));
    await tester.tap(find.text('Tracked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('long-press selects; remove then undo', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.longPress(find.text('Akira'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Akira'), findsOneWidget);
  });

  testWidgets('keyboard: Select, select all, Escape exits', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Exit selection'));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('set categories for the selection', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    await tester.longPress(find.text('Akira'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Set categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Reading'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final m = (await tester.runAsync(
      () => f.deps.repos.categories.watchMembership().first,
    ))!;
    expect(m[_a], {'x'});
    // Akira left "Default": the selection ends so nothing hidden stays picked.
    expect(find.text('Akira'), findsNothing);
    expect(find.text('Library'), findsOneWidget);
    await tester.longPress(find.text('Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Set categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('edit categories opens the categories screen', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.byTooltip('Edit categories'));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);
  });
}
