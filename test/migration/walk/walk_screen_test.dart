import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/walk/walk_controller.dart';
import 'package:kartka/migration/walk/walk_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes.dart';
import 'walk_fakes.dart';

Future<MigrationWalkController> _pump(WidgetTester t, WalkWorld w) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(w.world.tracking.dispose);
  final c = w.controller();
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MigrationWalkScreen(controller: c),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

Finder _spoken(String label) =>
    find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);

Finder _card(String url) => find.byKey(ValueKey('candidate-$url'));

void main() {
  testWidgets('shows the entry and its alternatives; a tap on a card '
      'migrates it and goes to the next entry', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk']);
    w.old.chapterLists['/One Piece'] = chaptersOf('/op', [1, 2, 3]);
    w.best.chapterLists['/best/One Piece'] = chaptersOf('/b', [1, 2, 3, 4]);
    final c = await _pump(t, w);
    expect(find.text('One Piece'), findsWidgets);
    expect(find.text('Old Site'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Best Site'), findsWidgets);
    expect(find.text('1 / 2'), findsOneWidget);
    await t.tap(_card('/best/One Piece'));
    await t.pumpAndSettle();
    expect(c.migrated, 1);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(_card('/best/Berserk'), findsOneWidget);
  });

  testWidgets('skip goes to the next entry, back returns', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk']);
    await _pump(t, w);
    await t.tap(_spoken('Skip'));
    await t.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await t.tap(_spoken('Previous entry'));
    await t.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await t.tap(_spoken('Skip'));
    await t.pumpAndSettle();
    await t.tap(_spoken('Skip'));
    await t.pumpAndSettle();
    expect(_spoken('Done. Migrated 0, failed 0'), findsOneWidget);
  });

  testWidgets('a failed source shows an icon on its lane, the others still '
      'give cards, and no exception text is painted', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    w
      ..best.searchError = StateError(
        'SuwayomiException: Exception while fetching data '
        '(/fetchSourceManga) : HTTP error 400',
      )
      ..good.offer('One Piece', 'One Piece', '/good/op');
    await _pump(t, w);
    expect(_spoken('Search failed on Best Site'), findsOneWidget);
    expect(_card('/good/op'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('no match shows an icon; a manual search finds one', (t) async {
    final w = WalkWorld();
    await w.world.add('Kishi');
    w.good.offer('Knight and Penguin', 'Knight and Penguin', '/good/kp');
    await _pump(t, w);
    expect(_spoken('No alternative found'), findsOneWidget);
    await t.tap(_spoken('Search by hand'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Knight and Penguin');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(_card('/good/kp'), findsOneWidget);
  });

  testWidgets('a failed backup shows an icon and nothing moves', (t) async {
    final w = WalkWorld(backups: BrokenBlobStore());
    await w.library(['One Piece']);
    final c = await _pump(t, w);
    await t.tap(_card('/best/One Piece'));
    await t.pumpAndSettle();
    expect(c.migrated, 0);
    expect(_spoken('Nothing changed: the backup failed'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
  });

  testWidgets('an empty walk says so', (t) async {
    await _pump(t, WalkWorld());
    expect(find.bySemanticsLabel(RegExp('^Nothing to migrate')), findsOne);
  });

  testWidgets('a weak match shows its meter and date; the end shows the '
      'outcome; back shows where an entry went', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk']);
    await w.world.repos.progress.record(
      ReadingProgress(
        key: mangaKeyOf('old', '/One Piece'),
        chapterUrl: '/op/100',
        chapterNumber: 100,
        page: 0,
        readAt: DateTime.utc(2026),
      ),
    );
    w.good.offerFull(
      'One Piece',
      'One Peice',
      '/good/op',
      chapterCount: 1,
      newest: DateTime.utc(2026, 3, 4),
    );
    final c = await _pump(t, w);
    expect(find.text('2026-03-04'), findsOneWidget);
    expect(find.byIcon(Icons.signal_cellular_alt_1_bar), findsOneWidget);
    await t.tap(_card('/best/One Piece'));
    await t.pumpAndSettle();
    w.best.chaptersError = StateError('gone');
    await t.tap(_card('/best/Berserk'));
    await t.pumpAndSettle();
    expect(c.failed, 1);
    await t.tap(_spoken('Skip'));
    await t.pumpAndSettle();
    expect(_spoken('Done. Migrated 1, failed 1'), findsOneWidget);
    expect(_spoken('Failed'), findsOneWidget);
    expect(find.text('backups/kartka-backup-20261025T123005Z.json'), findsOne);
    await t.tap(_spoken('Previous entry'));
    await t.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await t.tap(_spoken('Previous entry'));
    await t.pumpAndSettle();
    expect(_card('/best/One Piece'), findsOneWidget);
    expect(_card('/good/op'), findsNothing);
  });

  testWidgets('a spinner shows while the entry is searched', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    final gate = w.best.gate = Completer<void>();
    final c = w.controller();
    addTearDown(w.world.tracking.dispose);
    await t.pumpWidget(MaterialApp(home: MigrationWalkScreen(controller: c)));
    await t.pump();
    await t.pump();
    expect(find.bySemanticsLabel('Searching…'), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(_card('/best/One Piece'), findsOneWidget);
  });
}
