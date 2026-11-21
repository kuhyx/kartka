import 'dart:async';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/migration/walk/walk_screen.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:material_ui/material_ui.dart';

import 'walk_fakes.dart';

/// A blob store whose writes wait for [gate].
class _SlowBlobStore extends MemoryBlobStore {
  final gate = Completer<void>();

  @override
  Future<void> put(String key, Uint8List bytes) async {
    await gate.future;
    await super.put(key, bytes);
  }
}

Finder _spoken(String label) =>
    find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);

Future<void> _pump(WidgetTester t, WalkWorld w) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(w.world.tracking.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MigrationWalkScreen(controller: w.controller()),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the auto-fix button migrates the strong matches and stops '
      'on the weak one', (t) async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk', 'Vagabond']);
    w
      ..strong('One Piece')
      ..strong('Berserk');
    await _pump(t, w);
    await t.tap(_spoken('Migrate every strong match'));
    await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_spoken('Migrate every strong match'), findsOneWidget);
    expect(_spoken('Stop'), findsNothing);
  });

  testWidgets('while it runs it shows a count and a stop button; the other '
      'actions wait', (t) async {
    final backups = _SlowBlobStore();
    final w = WalkWorld(backups: backups);
    await w.library(['One Piece', 'Berserk']);
    w
      ..strong('One Piece')
      ..strong('Berserk');
    await _pump(t, w);
    await t.tap(_spoken('Migrate every strong match'));
    await t.pump();
    expect(_spoken('Migrated'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    final skip = find.ancestor(
      of: _spoken('Skip'),
      matching: find.byType(IconButton),
    );
    expect(t.widget<IconButton>(skip).onPressed, isNull);
    await t.tap(_spoken('Stop'));
    backups.gate.complete();
    await t.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(_spoken('Stop'), findsNothing);
  });
}
