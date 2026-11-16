import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/app/shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_platform.dart';

/// One main screen under the fit check: the real screen widget with fake
/// data large enough to need several pages.
class FitScreen {
  /// Describes the screen.
  const new({
    required this.tab,
    required this.screen,
    required this.tiles,
    this.search,
  });

  /// The shell tab the screen fills.
  final KartkaTab tab;

  /// Builds the real screen. Seeding happens before the pump.
  final WidgetBuilder screen;

  /// The primary tiles (covers, source tiles, health tiles).
  final Finder tiles;

  /// The search field, for screens that have one (keyboard variant).
  final Finder? search;
}

/// Pixel 6a: 1080x2400 physical, dpr 2.625, status bar 132 px, gesture
/// nav 63 px (physical px from `adb shell dumpsys window`).
void pixel6a(WidgetTester tester, {double keyboard = 0}) {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = const FakeViewPadding(top: 132, bottom: 63)
    ..viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

/// Settles without waiting forever on spinners or endless animations.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps the real shell with [s] in its tab and switches to it.
Future<void> pumpInShell(
  WidgetTester tester,
  FitScreen s, {
  double keyboard = 0,
}) async {
  pixel6a(tester, keyboard: keyboard);
  final platform = fakePlatform();
  final registry = KartkaRegistry.build(platform, [
    (_) => KartkaFeature(id: 'fit', tabs: {s.tab: s.screen}),
  ]);
  await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
  await settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(tabInfo[s.tab]!.icon),
    ),
  );
  await settle(tester);
}

/// The tab fits: no vertical scrolling anywhere on screen, at least one
/// full row of tiles, every shown tile hit-testable above the nav bar and
/// overflow on further horizontal pages.
void expectFits(WidgetTester tester, FitScreen s) {
  for (final e in find.byType(Scrollable).evaluate()) {
    final state = (e as StatefulElement).state as ScrollableState;
    if (axisDirectionToAxis(state.axisDirection) != Axis.vertical) continue;
    expect(
      state.position.maxScrollExtent,
      0,
      reason:
          '${tabInfo[s.tab]!.semanticLabel}: ${e.widget} scrolls vertically',
    );
  }
  final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
  final tiles = s.tiles.evaluate().toList();
  expect(tiles.length, greaterThanOrEqualTo(2), reason: 'no tiles shown');
  for (final e in tiles) {
    final box = e.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // Tiles on other pages of the PageView sit off to the side.
    if (rect.left >= 412 || rect.right <= 0) continue;
    expect(rect.bottom, lessThanOrEqualTo(navTop + 0.5), reason: '$rect');
    expect(rect.top, greaterThanOrEqualTo(132 / 2.625 - 0.5));
    final hit = HitTestResult();
    tester.binding.hitTestInView(hit, rect.center, tester.view.viewId);
    expect(
      hit.path.any((h) => h.target == box || _below(h.target, box)),
      isTrue,
      reason: 'tile at $rect is covered',
    );
  }
  final dot = find.byKey(const ValueKey<String>('fit-grid-dot-1'));
  expect(dot, findsOneWidget, reason: 'the data should need a second page');
  // A gap above the dots, so the last row's edge and shadow are not cut.
  final dotTop = tester.getTopLeft(dot).dy;
  for (final e in tiles) {
    final box = e.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.left >= 412 || rect.right <= 0) continue;
    expect(rect.bottom + 8, lessThanOrEqualTo(dotTop), reason: '$rect');
  }
}

/// With more pages than dots fit across, the indicator still fits the
/// screen width (no overflow) and says where you are.
void expectPageCounter(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final counter = find.byKey(const ValueKey<String>('fit-grid-pages'));
  expect(counter, findsOneWidget);
  expect(tester.getRect(counter).right, lessThanOrEqualTo(412));
}

bool _below(HitTestTarget target, RenderBox tile) {
  if (target is! RenderObject) return false;
  for (RenderObject? o = target; o != null; o = o.parent) {
    if (o == tile) return true;
  }
  return false;
}

/// With the keyboard open the search field stays visible above it and
/// nothing scrolls.
void expectSearchVisible(WidgetTester tester, FitScreen s) {
  final field = tester.getRect(s.search!);
  const keyboardTop = 2400 / 2.625 - 300 / 2.625;
  expect(field.bottom, lessThanOrEqualTo(keyboardTop), reason: '$field');
  expect(field.top, greaterThanOrEqualTo(132 / 2.625 - 0.5));
  expect(tester.takeException(), isNull);
}
