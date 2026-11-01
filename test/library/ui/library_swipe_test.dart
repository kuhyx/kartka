import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/ui/library_swipe.dart';

import '../support/fakes.dart';
import 'harness.dart';

const _a = 'mangadex|/manga/aaa';
const _b = 'mangadex|/manga/bbb';
const _c = 'mangadex|/manga/ccc';

/// Akira is in "1", Berserk in "8"; Claymore is uncategorised ("Default").
Future<Fakes> _seed({bool categories = true}) async {
  final f = Fakes();
  final lib = f.deps.repos.library;
  await lib.upsert(entry('/manga/aaa', title: 'Akira', addedDays: 1));
  await lib.upsert(entry('/manga/bbb', title: 'Berserk'));
  await lib.upsert(entry('/manga/ccc', title: 'Claymore', addedDays: 2));
  if (!categories) return f;
  final cats = f.deps.repos.categories;
  await cats.upsert(Category(id: 'one', name: '1', order: 0, updatedAt: t0));
  await cats.upsert(Category(id: 'eight', name: '8', order: 1, updatedAt: t0));
  await cats.setMembership(_a, 'one', true);
  await cats.setMembership(_b, 'eight', true);
  return f;
}

int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

Future<void> _fling(WidgetTester tester, double dx) async {
  await tester.fling(find.byType(CategorySwipe), Offset(dx, 0), 2000);
  await tester.pumpAndSettle();
}

void _shows({
  required bool akira,
  required bool berserk,
  bool claymore = false,
}) {
  expect(find.text('Akira'), akira ? findsOneWidget : findsNothing);
  expect(find.text('Berserk'), berserk ? findsOneWidget : findsNothing);
  expect(find.text('Claymore'), claymore ? findsOneWidget : findsNothing);
}

void main() {
  test('wrapIndex wraps both ways and ignores a single tab', () {
    expect(wrapIndex(2, 1, 3), 0);
    expect(wrapIndex(0, -1, 3), 2);
    expect(wrapIndex(0, 1, 3), 1);
    expect(wrapIndex(0, 1, 1), 0);
  });

  testWidgets('fling left on the first tab goes to the second', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    expect(_tabIndex(tester), 0);
    await _fling(tester, -300);
    expect(_tabIndex(tester), 1);
    _shows(akira: true, berserk: false);
  });

  testWidgets('fling left on the last tab wraps to Default', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 2);
    await _fling(tester, -300);
    expect(_tabIndex(tester), 0);
    _shows(akira: false, berserk: false, claymore: true);
  });

  testWidgets('fling right on Default wraps to the last tab', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await _fling(tester, 300);
    expect(_tabIndex(tester), 2);
    _shows(akira: false, berserk: true);
  });

  testWidgets('slow long drag also switches; short slow one does not', (
    tester,
  ) async {
    await pumpLibrary(tester, (await _seed()).deps);
    final at = tester.getCenter(find.byType(CategorySwipe));
    final g = await tester.startGesture(at);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 1);
    await tester.timedDrag(
      find.byType(CategorySwipe),
      const Offset(-150, 0),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 1);
  });

  testWidgets('a short fast flick does not switch', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    for (final dx in [-30.0, 30.0, -100.0]) {
      await tester.fling(find.byType(CategorySwipe), Offset(dx, 0), 3000);
      await tester.pumpAndSettle();
      expect(_tabIndex(tester), 0);
    }
  });

  testWidgets('a manga given a category leaves Default; empty Default hides', (
    tester,
  ) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('All'), findsNothing);
    _shows(akira: false, berserk: false, claymore: true);
    await f.deps.repos.categories.setMembership(_c, 'one', true);
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsNothing);
    expect(_tabIndex(tester), 0);
    _shows(akira: true, berserk: false, claymore: true);
    await _fling(tester, -300);
    expect(_tabIndex(tester), 1);
    _shows(akira: false, berserk: true);
    await f.deps.repos.categories.setMembership(_a, 'one', false);
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);
    expect(_tabIndex(tester), 2);
  });

  testWidgets('vertical drag does not change the tab', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    await tester.fling(find.byType(CategorySwipe), const Offset(0, -300), 2000);
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 0);
    _shows(akira: false, berserk: false, claymore: true);
  });

  testWidgets('tabs follow when a category is added', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    await f.deps.repos.categories.upsert(
      Category(id: 'nine', name: '9', order: 2, updatedAt: t0),
    );
    await tester.pumpAndSettle();
    await _fling(tester, 300);
    expect(_tabIndex(tester), 3);
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('no categories: a swipe changes nothing', (tester) async {
    await pumpLibrary(tester, (await _seed(categories: false)).deps);
    expect(find.byType(TabBar), findsNothing);
    await _fling(tester, -300);
    await _fling(tester, 300);
    _shows(akira: true, berserk: true, claymore: true);
  });
}
