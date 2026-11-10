import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/migration_controller.dart';
import 'package:kartka/migration/migration_outcome.dart';
import 'package:kartka/migration/migration_screen.dart';

import 'fakes.dart';

Future<World> _world() async {
  final w = World()..install();
  await w.add('One Piece');
  await w.add('Berserk');
  await w.add('Vagabond');
  w.target
    ..offer('One Piece', 'One Piece', '/atsu/op')
    ..offer('Berserk', 'Berserk: Deluxe', '/atsu/b');
  return w;
}

Future<void> _pump(WidgetTester t, World w) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(w.tracking.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MigrationScreen(controller: MigrationController(w.deps)),
    ),
  );
  await t.pumpAndSettle();
}

Finder _box(String title) => find.descendant(
  of: find.widgetWithText(CheckboxListTile, title),
  matching: find.byType(Checkbox),
);

bool _ticked(WidgetTester t, String title) =>
    t.widget<Checkbox>(_box(title)).value ?? false;

/// The word-free glyph spoken as [label].
Finder _spoken(String label) =>
    find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);

/// The Apply button showing [count] ticked entries.
Finder _apply(int count) => find.ancestor(
  of: find.text('$count'),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

void main() {
  testWidgets('lists each entry with its best match', (t) async {
    final w = await _world();
    await _pump(t, w);
    expect(_spoken('Migrate to Atsumaru'), findsOneWidget);
    expect(_spoken('Exact match'), findsOneWidget);
    expect(find.text('One Piece'), findsNWidgets(2));
    expect(_spoken('Best match'), findsOneWidget);
    expect(find.text('Berserk: Deluxe'), findsOneWidget);
    expect(_spoken('No match on Atsumaru'), findsOneWidget);
    expect(_ticked(t, 'One Piece'), isTrue);
    expect(_ticked(t, 'Berserk'), isFalse);
    expect(t.widget<Checkbox>(_box('Vagabond')).onChanged, isNull);
    expect(_apply(1), findsOneWidget);
    expect(_spoken('Apply'), findsOneWidget);
  });

  testWidgets('two entries matched to one Atsumaru entry say so', (t) async {
    final w = await _world();
    w.target.offer('Vagabond', 'One Piece', '/atsu/op');
    await _pump(t, w);
    expect(_spoken('They merge: same Atsumaru entry as'), findsNWidgets(2));
    expect(find.text('Vagabond'), findsNWidgets(2));
    expect(find.text('One Piece'), findsNWidgets(4));
  });

  testWidgets('nothing is written until Apply is tapped', (t) async {
    final w = await _world();
    final before = await t.runAsync(w.entries);
    await _pump(t, w);
    await t.pump(const Duration(minutes: 1));
    expect(await t.runAsync(w.entries), before);
    expect(await t.runAsync(() => w.backups.list('backups')), isEmpty);
  });

  testWidgets('ticking a best match, then Apply migrates both', (t) async {
    final w = await _world();
    await _pump(t, w);
    await t.tap(_box('Berserk'));
    await t.pumpAndSettle();
    expect(_apply(2), findsOneWidget);
    await t.tap(_apply(2));
    await t.pumpAndSettle();
    expect(_spoken('Migrated'), findsOneWidget);
    expect(_spoken('Failed'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(MigrationOutcome),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('backups/kartka-backup-20261025T123005Z.json'),
      findsOneWidget,
    );
    final urls = (await t.runAsync(w.entries))!.values.map((e) => e.mangaUrl);
    expect(urls, unorderedEquals(['/atsu/op', '/atsu/b', '/Vagabond']));
  });

  testWidgets('a failed entry is reported', (t) async {
    final w = await _world();
    await _pump(t, w);
    w.target.chaptersError = StateError('gone');
    await t.tap(_apply(1));
    await t.pumpAndSettle();
    final outcome = find.byType(MigrationOutcome);
    expect(_spoken('Failed'), findsOneWidget);
    expect(find.descendant(of: outcome, matching: find.text('0')), findsOne);
    expect(find.descendant(of: outcome, matching: find.text('1')), findsOne);
    expect(find.text('Bad state: gone'), findsOneWidget);
  });

  testWidgets('without Atsumaru there is nothing to apply', (t) async {
    final w = await _world();
    w.lookup = () => null;
    await _pump(t, w);
    expect(
      find.bySemanticsLabel(RegExp('^Atsumaru is not available')),
      findsOneWidget,
    );
    expect(_spoken('Apply'), findsNothing);
  });

  testWidgets('an empty review says so', (t) async {
    final w = World()..install();
    await _pump(t, w);
    expect(
      find.bySemanticsLabel(RegExp('^Nothing to migrate')),
      findsOneWidget,
    );
  });

  testWidgets('a failed backup changes nothing', (t) async {
    final w = World(backups: BrokenBlobStore())..install();
    await w.add('One Piece');
    w.target.offer('One Piece', 'One Piece', '/atsu/op');
    await _pump(t, w);
    await t.tap(_apply(1));
    await t.pumpAndSettle();
    expect(_spoken('Nothing changed: the backup failed'), findsOneWidget);
    expect(find.text('Bad state: disk full'), findsOneWidget);
    expect((await t.runAsync(w.entries))!.keys, [
      mangaKeyOf('old', '/One Piece'),
    ]);
  });

  testWidgets('leaving mid-search stops searching', (t) async {
    final w = await _world();
    final gate = w.target.gate = Completer<void>();
    final c = MigrationController(w.deps);
    await t.pumpWidget(MaterialApp(home: MigrationScreen(controller: c)));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    gate.complete();
    await t.pumpAndSettle();
    expect(c.phase, MigrationPhase.searching);
    expect(w.target.searched, hasLength(1));
    await w.tracking.dispose();
  });
}
