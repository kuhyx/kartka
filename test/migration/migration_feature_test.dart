import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/migration_feature.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/migration/walk/walk_screen.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

final MangaKey _key = mangaKeyOf('old', '/One Piece');

LibraryEntry _entry(String title) => LibraryEntry(
  key: mangaKeyOf('old', '/$title'),
  sourceId: 'old',
  mangaUrl: '/$title',
  title: title,
  addedAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

/// The feature over fresh repositories holding One Piece and Berserk.
/// Built inside each test: futures made outside a widget test's fake
/// zone never complete inside it.
Future<({KartkaFeature feature, ScriptedSource atsu})> _setup() async {
  final repos = LibraryRepositories(
    MemoryKeyValueStore(),
    decorators: () => const [],
  );
  await repos.library.upsert(_entry('One Piece'));
  await repos.library.upsert(_entry('Berserk'));
  final atsu = ScriptedSource(atsumaruSourceId, name: 'Atsumaru')
    ..offer('One Piece', 'One Piece', '/atsu/op');
  final env = KartkaEnv(memoryPlatform());
  final feature = migrationFeature(env);
  env.registry = KartkaRegistry([
    KartkaFeature(
      id: 'deps',
      services: [
        repos,
        StaticSourceProvider([atsu]),
      ],
    ),
    feature,
  ]);
  return (feature: feature, atsu: atsu);
}

MangaDetails _details(String sourceId) => MangaDetails(
  sourceId: sourceId,
  url: '/One Piece',
  title: 'One Piece',
  status: MangaStatus.ongoing,
);

Future<void> _pump(WidgetTester t, KartkaFeature f, Widget home) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      ...f.routes,
    ],
  );
  await t.pumpWidget(
    MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
}

void main() {
  test('route urls carry the keys to review', () {
    expect(migrateRouteFor(const []), migrateRoute);
    expect(Uri.parse(migrateRouteFor(['a|/x?y'])).queryParametersAll, {
      'key': ['a|/x?y'],
    });
  });

  testWidgets('the More tile walks the whole library', (t) async {
    final s = await _setup();
    await _pump(t, s.feature, Builder(builder: s.feature.settingsTiles.first));
    await t.tap(find.byIcon(Icons.swap_horiz));
    await t.pumpAndSettle();
    expect(find.byType(MigrationWalkScreen), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-/atsu/op')), findsOneWidget);
  });

  testWidgets('the detail slot walks that entry only', (t) async {
    final s = await _setup();
    final slot = s.feature.services.whereType<MangaDetailSlot>().single;
    await _pump(
      t,
      s.feature,
      Builder(builder: (c) => slot.build(c, _key, _details('old'))),
    );
    await t.tap(find.bySemanticsLabel('Migrate'));
    await t.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(s.atsu.searched, ['One Piece']);
  });

  testWidgets('the slot shows on library entries only, Atsumaru ones too', (
    t,
  ) async {
    final s = await _setup();
    final slot = s.feature.services.whereType<MangaDetailSlot>().single;
    await _pump(
      t,
      s.feature,
      Column(
        children: [
          Builder(
            builder: (c) =>
                slot.build(c, mangaKeyOf('old', '/Not saved'), _details('old')),
          ),
          Builder(
            builder: (c) => slot.build(c, _key, _details(atsumaruSourceId)),
          ),
        ],
      ),
    );
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    slot
      ..opened(_key) // Nothing to do when the screen opens,
      ..loaded(_key); // nor once it has loaded.
  });

  testWidgets('a candidate previews its first pages through the platform', (
    t,
  ) async {
    final s = await _setup();
    s.atsu.chapterLists['/atsu/op'] = const [
      ChapterInfo(url: '/atsu/op/1', name: '1', number: 1),
    ];
    await _pump(t, s.feature, Builder(builder: s.feature.settingsTiles.first));
    await t.tap(find.byIcon(Icons.swap_horiz));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.photo_library_outlined));
    await t.pumpAndSettle();
    // Fake page urls have no scheme the loader knows: each is a broken page.
    expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(3));
  });
}
