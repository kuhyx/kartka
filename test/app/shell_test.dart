import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';

import '../helpers/fake_platform.dart';

KartkaFeature _library(KartkaEnv env) => KartkaFeature(
  id: 'lib',
  tabs: {KartkaTab.library: (_) => const Text('my library')},
  settingsTiles: [(_) => const ListTile(title: Text('Import backup'))],
  routes: [
    GoRoute(
      path: '/probe',
      builder: (context, _) =>
          Text('probe ${KartkaScope.of(context).registry.features.length}'),
    ),
  ],
);

Future<KartkaRegistry> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platform = fakePlatform();
  final registry = KartkaRegistry.build(platform, [_library]);
  await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
  await tester.pumpAndSettle();
  return registry;
}

void main() {
  testWidgets('phone: bottom navigation with five tabs in order', (
    tester,
  ) async {
    await _pump(tester, const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      [for (final d in bar.destinations) (d as NavigationDestination).label],
      ['Library', 'Updates', 'Browse', 'Sources', 'More'],
    );
    expect(find.text('my library'), findsOneWidget);

    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    expect(find.text('Updates is not built yet'), findsOneWidget);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.text('Browse is not built yet'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Import backup'), findsOneWidget);
  });

  testWidgets('desktop: navigation rail, keyboard reachable', (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Sources is not built yet'), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(5));
  });

  testWidgets('feature routes are mounted and see KartkaScope', (tester) async {
    await _pump(tester, const Size(400, 800));
    final context = tester.element(find.byType(NavigationBar));
    expect(KartkaScope.of(context).platform, isNotNull);
    GoRouter.of(context).go('/probe');
    await tester.pumpAndSettle();
    expect(find.text('probe 1'), findsOneWidget);
  });

  testWidgets('More shows an empty state when no tiles exist', (tester) async {
    final platform = fakePlatform();
    final registry = KartkaRegistry.build(platform, []);
    await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to configure yet'), findsOneWidget);
  });
}
