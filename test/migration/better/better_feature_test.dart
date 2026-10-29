import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/better/better_screen.dart';
import 'package:kartka/migration/better/better_wiring.dart';
import 'package:kartka/migration/migration_feature.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import '../../source_health/ui/harness.dart';
import '../fakes.dart';

/// The real source-health and migration parts over memory stores: the
/// library holds One Piece on a cut source, `best` is an installed keep
/// source that has it.
Future<KartkaRegistry> _registry() async {
  final repos = LibraryRepositories(
    MemoryKeyValueStore(),
    decorators: () => const [],
  );
  await repos.library.upsert(
    LibraryEntry(
      key: mangaKeyOf('old', '/op'),
      sourceId: 'old',
      mangaUrl: '/op',
      title: 'One Piece',
      addedAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    ),
  );
  final best = ScriptedSource('best', name: 'Best Site')
    ..offer('One Piece', 'One Piece', '/best/op');
  const records = [
    SourceHealthRecord(
      id: 'best',
      name: 'Best Site',
      rank: 1,
      verdict: HealthVerdict.keep,
    ),
    SourceHealthRecord(
      id: 'old',
      name: 'Old Site',
      rank: 2,
      verdict: HealthVerdict.cut,
    ),
  ];
  return KartkaRegistry.build(memoryPlatform(), [
    sourceHealthFeature,
    migrationFeature,
    (_) => KartkaFeature(
      id: 'deps',
      services: [
        repos,
        InMemoryRtdbReader({
          'source_health': {for (final r in records) r.id: r.toJson()},
        }),
        StaticSourceProvider([ScriptedSource('old', name: 'Old Site'), best]),
      ],
    ),
  ]);
}

Future<void> _pump(WidgetTester t, KartkaRegistry r, WidgetBuilder home) async {
  tallSurface(t);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (c, _) => Scaffold(body: home(c)),
      ),
      ...r.routes,
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
  );
  await _settle(t);
}

/// Spinners never settle, so pump a while instead.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('the More tile opens the screen with the suggestion', (t) async {
    final r = await _registry();
    final tiles = r.settingsTiles;
    await _pump(t, r, (c) => Column(children: [for (final b in tiles) b(c)]));
    await t.tap(find.text('Migrate to better sources'));
    await _settle(t);
    expect(find.byType(BetterSourcesScreen), findsOne);
    expect(find.text('Old Site → Best Site'), findsOne);
  });

  testWidgets('the Sources tab links the screen', (t) async {
    final r = await _registry();
    await _pump(t, r, r.tab(KartkaTab.sources)!);
    await t.tap(find.byKey(const Key('migrate-better')));
    await _settle(t);
    expect(find.byType(BetterSourcesScreen), findsOne);
  });

  test('without a health feed the ranking reads as empty', () async {
    expect(await healthRecords(null), isEmpty);
    expect(
      await healthRecords(ControlledFeed(), timeout: Duration.zero),
      isEmpty,
    );
  });
}
