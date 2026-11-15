import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/ui/category_tabs.dart';
import 'package:kartka/library/ui/library_cell.dart';

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

Future<void> _tap(WidgetTester tester, String tab) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(tab)),
  );
  await tester.pumpAndSettle();
}

Future<void> _fling(WidgetTester tester, double dx) async {
  await tester.fling(find.byType(PageView), Offset(dx, 0), 2000);
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
  testWidgets('tapping a tab switches the category', (tester) async {
    await pumpLibrary(tester, (await _seed()).deps);
    expect(_tabIndex(tester), 0);
    _shows(akira: false, berserk: false, claymore: true);
    await _tap(tester, '1');
    expect(_tabIndex(tester), 1);
    _shows(akira: true, berserk: false);
    await _tap(tester, '8');
    expect(_tabIndex(tester), 2);
    _shows(akira: false, berserk: true);
  });

  testWidgets('a sideways swipe pages the grid, never the category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = Fakes();
    for (var i = 0; i < 30; i++) {
      await f.deps.repos.library.upsert(entry('/m/$i', title: 'M$i'));
    }
    await f.deps.repos.categories.upsert(
      Category(id: 'one', name: '1', order: 0, updatedAt: t0),
    );
    await f.deps.repos.categories.setMembership('mangadex|/m/0', 'one', true);
    await pumpLibrary(tester, f.deps);
    final firstPage = find.byType(LibraryCell).hitTestable();
    final before = tester.widgetList(firstPage).map((w) => w.key).toSet();
    await _fling(tester, -300);
    expect(_tabIndex(tester), 0);
    final after = tester.widgetList(firstPage).map((w) => w.key).toSet();
    expect(after.intersection(before), isEmpty);
    expect(after, isNotEmpty);
    await _tap(tester, '1');
    // A new tab starts on its first page.
    expect(find.text('M0'), findsOneWidget);
  });

  testWidgets('a manga given a category leaves Default; empty Default hides', (
    tester,
  ) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    expect(find.bySemanticsLabel(RegExp('^Default')), findsOneWidget);
    expect(find.text('All'), findsNothing);
    _shows(akira: false, berserk: false, claymore: true);
    await f.deps.repos.categories.setMembership(_c, 'one', true);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Default')), findsNothing);
    expect(_tabIndex(tester), 0);
    _shows(akira: true, berserk: false, claymore: true);
    await _tap(tester, '8');
    expect(_tabIndex(tester), 1);
    _shows(akira: false, berserk: true);
    await f.deps.repos.categories.setMembership(_a, 'one', false);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Default')), findsOneWidget);
    expect(_tabIndex(tester), 2);
  });

  testWidgets('tabs follow when a category is added', (tester) async {
    final f = await _seed();
    await pumpLibrary(tester, f.deps);
    await f.deps.repos.categories.upsert(
      Category(id: 'nine', name: '9', order: 2, updatedAt: t0),
    );
    await tester.pumpAndSettle();
    await _tap(tester, '9');
    expect(_tabIndex(tester), 3);
    expect(find.bySemanticsLabel('No matches'), findsOneWidget);
  });

  testWidgets('no categories: no tab bar, everything shows', (tester) async {
    await pumpLibrary(tester, (await _seed(categories: false)).deps);
    expect(find.byType(TabBar), findsNothing);
    _shows(akira: true, berserk: true, claymore: true);
  });

  testWidgets('an outside index change animates the same bar', (tester) async {
    Widget bar(int index) => MaterialApp(
      home: Scaffold(
        appBar: CategoryTabs(
          labels: const [null, '1', '8'],
          index: index,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(bar(0));
    await tester.pumpWidget(bar(2));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 2);
  });
}
