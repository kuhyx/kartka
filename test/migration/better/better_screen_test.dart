import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/better/better_controller.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/migration/better/better_screen.dart';
import 'package:kartka/migration/migration_outcome.dart';

import '../fakes.dart';
import 'better_fakes.dart';

Future<BetterWorld> _world() async {
  final b = BetterWorld();
  await b.world.add('One Piece');
  await b.world.add('Berserk');
  await b.world.add('Vagabond');
  b.old.chapterLists['/One Piece'] = chaptersOf('/old/op', [1, 2]);
  b.best
    ..offer('One Piece', 'One Piece', '/best/op')
    ..chapterLists['/best/op'] = chaptersOf('/best/op', [1, 2, 3]);
  b.good.offer('Berserk', 'Berserk!', '/good/b');
  return b;
}

Future<void> _pump(WidgetTester t, BetterSourcesController c) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: BetterSourcesScreen(controller: c),
    ),
  );
  await t.pumpAndSettle();
}

Finder _migrateOf(String title) =>
    find.byKey(ValueKey('migrate-${mangaKeyOf('old', '/$title')}'));

/// The word-free glyph spoken as [label].
Finder _spoken(String label) =>
    find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);

Finder _migrateAll() => find.ancestor(
  of: _spoken('Migrate all'),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

void main() {
  testWidgets('each row shows current → suggested source, the match, the '
      'chapter counts and a Migrate button', (t) async {
    final b = await _world();
    addTearDown(b.world.tracking.dispose);
    await _pump(t, b.controller());
    expect(_spoken('Migrate to better sources'), findsOne);
    expect(find.text('Old Site → Best Site'), findsOne);
    expect(_spoken('Exact match'), findsOne);
    expect(find.text('One Piece'), findsNWidgets(2));
    expect(find.text('2 → 3'), findsOne);
    expect(find.text('Old Site → Good Site'), findsOne);
    expect(_spoken('Close match'), findsOne);
    expect(find.text('Berserk!'), findsOne);
    expect(find.text('0 → 0'), findsOne);
    expect(_spoken('No Keep source has this title'), findsOne);
    expect(_spoken('its source is cut'), findsNWidgets(3));
    expect(find.byIcon(Icons.content_cut), findsNWidgets(3));
    expect(_migrateOf('One Piece'), findsOne);
    expect(_migrateOf('Vagabond'), findsNothing);
    expect(
      find.descendant(of: _migrateAll(), matching: find.text('2')),
      findsOne,
    );
    expect(t.getSize(_migrateOf('One Piece')).height, greaterThanOrEqualTo(48));
  });

  test('every move reason has its own glyph', () {
    final icons = {for (final r in MoveReason.values) reasonIcon(r)};
    expect(icons, hasLength(MoveReason.values.length));
  });

  testWidgets('Migrate moves that entry only', (t) async {
    final b = await _world();
    addTearDown(b.world.tracking.dispose);
    await _pump(t, b.controller());
    await t.tap(_migrateOf('One Piece'));
    await t.pumpAndSettle();
    expect(_spoken('Migrated'), findsNWidgets(2));
    final keys = (await t.runAsync(b.world.entries))!.keys;
    expect(keys, contains(mangaKeyOf('best', '/best/op')));
    expect(keys, contains(mangaKeyOf('old', '/Berserk')));
    expect(_spoken('Backup saved as'), findsOne);
    expect(find.textContaining('backups/'), findsOne);
  });

  testWidgets('Migrate all asks first: Cancel moves nothing, Migrate moves '
      'every suggested entry', (t) async {
    final b = await _world();
    addTearDown(b.world.tracking.dispose);
    await _pump(t, b.controller());
    await t.tap(_migrateAll());
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('2')),
      findsOne,
    );
    await t.tap(_spoken('Cancel'));
    await t.pumpAndSettle();
    expect((await t.runAsync(b.world.entries))!.length, 3);
    expect(_spoken('Migrated'), findsNothing);

    await t.tap(_migrateAll());
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: _spoken('Migrate'),
      ),
    );
    await t.pumpAndSettle();
    // Two rows plus the outcome line.
    expect(_spoken('Migrated'), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byType(MigrationOutcome),
        matching: find.text('2'),
      ),
      findsOne,
    );
    final keys = (await t.runAsync(b.world.entries))!.keys;
    expect(keys, contains(mangaKeyOf('good', '/good/b')));
    expect(keys, contains(mangaKeyOf('old', '/Vagabond')));
  });

  testWidgets('a library on healthy keep sources has nothing to migrate', (
    t,
  ) async {
    final b = BetterWorld();
    addTearDown(b.world.tracking.dispose);
    await b.world.add('Healthy', sourceId: 'fine');
    await _pump(t, b.controller());
    expect(find.bySemanticsLabel(RegExp('^Nothing to migrate')), findsOne);
  });

  testWidgets('a failed backup is shown and nothing moves', (t) async {
    final w = World(backups: BrokenBlobStore());
    addTearDown(w.tracking.dispose);
    final b = await _world();
    addTearDown(b.world.tracking.dispose);
    await w.add('One Piece');
    await _pump(
      t,
      BetterSourcesController(
        w.deps,
        BetterSourcesInputs(
          records: () async => b.records,
          sources: () async => b.installed,
        ),
      ),
    );
    await t.tap(_migrateOf('One Piece'));
    await t.pumpAndSettle();
    expect(_spoken('Nothing changed: the backup failed'), findsOne);
    expect(_spoken('Migrated'), findsNothing);
  });
}
