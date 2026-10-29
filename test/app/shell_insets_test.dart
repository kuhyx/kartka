import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';

import '../helpers/fake_platform.dart';

// Stand-ins sit at the very top of their tab with no AppBar, like the real
// Sources tab: a centred placeholder would pass without any inset.
Widget _top(String text) =>
    Align(alignment: Alignment.topLeft, child: Text(text));

KartkaFeature _tabs(KartkaEnv env) => KartkaFeature(
  id: 'tabs',
  tabs: {
    KartkaTab.library: (_) => _top('library top'),
    KartkaTab.updates: (_) => _top('updates top'),
    KartkaTab.browse: (_) => _top('browse top'),
    KartkaTab.sources: (_) => _top('sources top'),
  },
  settingsTiles: [(_) => const ListTile(title: Text('more top'))],
);

const _statusBar = 40.0;

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // The status bar: MaterialApp reads padding from the view, so an outer
  // MediaQuery would not reach the tabs.
  tester.view.padding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  final platform = fakePlatform();
  final registry = KartkaRegistry.build(platform, [_tabs]);
  await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
  await tester.pumpAndSettle();
}

Future<void> _expectBelowStatusBar(
  WidgetTester tester,
  String tab,
  String content,
) async {
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
  expect(
    tester.getTopLeft(find.text(content)).dy,
    greaterThanOrEqualTo(_statusBar),
    reason: '$tab content sits under the status bar',
  );
}

void main() {
  for (final (name, size) in [
    ('phone', const Size(400, 800)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: every tab starts below the status bar', (t) async {
      await _pump(t, size);
      await _expectBelowStatusBar(t, 'Library', 'library top');
      await _expectBelowStatusBar(t, 'Updates', 'updates top');
      await _expectBelowStatusBar(t, 'Browse', 'browse top');
      await _expectBelowStatusBar(t, 'Sources', 'sources top');
      await _expectBelowStatusBar(t, 'More', 'more top');
    });
  }

  testWidgets('wide: the rail starts below the status bar', (t) async {
    await _pump(t, const Size(1280, 800));
    expect(
      t.getTopLeft(find.byType(NavigationRail)).dy,
      greaterThanOrEqualTo(_statusBar),
    );
  });
}
