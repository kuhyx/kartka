import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import 'fixtures.dart';

KartkaRegistry registryWith(List<Object> syncServices) =>
    KartkaRegistry.build(memoryPlatform(), [
      sourceHealthFeature,
      (_) => KartkaFeature(id: 'sync', services: syncServices),
    ]);

Future<void> pumpSourcesTab(WidgetTester tester, KartkaRegistry r) async {
  // Tall enough for the header (which grows with the stale banner once the
  // fixture is over a week old) plus a card; the lazy list builds no more.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(body: Builder(builder: r.tab(KartkaTab.sources)!)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('fills the Sources tab and supplies the browse lookup', () {
    final r = registryWith(const []);
    final f = r.features.first;
    expect(f.id, 'source-health');
    expect(f.tabs.keys, [KartkaTab.sources]);
    expect(r.maybe<SourceHealthLookup>(), isNotNull);
  });

  testWidgets('reads the ranking from the registered RtdbReader', (
    tester,
  ) async {
    final reader = InMemoryRtdbReader({
      'source_health': fixtureJson('rtdb_snapshot.json'),
    });
    await pumpSourcesTab(tester, registryWith([reader]));
    expect(find.byKey(const ValueKey('source-mangadex')), findsOne);
    final lookup = registryWith([reader]).maybe<SourceHealthLookup>()!;
    final summaries = await tester.runAsync(() => lookup.watch().first);
    expect(summaries!['mangadex']?.rank, 1);
  });

  testWidgets('the tab shows the ranking when Browse subscribed first', (
    tester,
  ) async {
    final reader = InMemoryRtdbReader({
      'source_health': fixtureJson('rtdb_snapshot.json'),
    });
    final r = registryWith([reader]);
    final browse = r.maybe<SourceHealthLookup>()!.watch().listen((_) {});
    await tester.runAsync(pumpEventQueue);
    await pumpSourcesTab(tester, r);
    expect(find.byKey(const ValueKey('source-mangadex')), findsOne);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(browse.cancel);
  });

  testWidgets('without sync the tab says so', (tester) async {
    await pumpSourcesTab(tester, registryWith(const []));
    expect(find.textContaining('sync'), findsOne);
  });
}
