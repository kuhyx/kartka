import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/import_controller.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/import_preview.dart';
import 'package:kartka/backup_import/import_screen.dart';
import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';

import 'fake_setup.dart';
import 'fakes.dart';
import 'fixture_builder.dart';

FakeFilePicker pickerOf(Uint8List bytes) => FakeFilePicker(
  files: [PickedFile(name: 'sy.tachibk', read: () async => bytes)],
);

Future<ImportController> _pump(WidgetTester tester, Uint8List bytes) async {
  final controller = ImportController(
    picker: pickerOf(bytes),
    importer: Fakes().importer,
    planner: (b) async => planBackupSync(b),
  );
  await tester.pumpWidget(
    MaterialApp(home: ImportScreen(controller: controller)),
  );
  return controller;
}

void main() {
  testWidgets('choose, dry-run summary, import, done', (tester) async {
    await _pump(tester, buildSyntheticTachibk());
    expect(find.bySemanticsLabel('Import SY backup'), findsOneWidget);
    expect(find.bySemanticsLabel('Choose backup file'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Choose backup file'));
    await tester.pumpAndSettle();
    expect(find.text('sy.tachibk'), findsOneWidget);
    expect(find.bySemanticsLabel('Library entries'), findsOneWidget);
    expect(find.bySemanticsLabel('Chapters read'), findsOneWidget);
    expect(find.bySemanticsLabel('Tracker links'), findsOneWidget);
    expect(find.textContaining('anilist '), findsOneWidget);
    expect(find.textContaining('mangaupdates '), findsOneWidget);
    expect(find.bySemanticsLabel('Source unavailable'), findsOneWidget);
    expect(find.text('E-Hentai (6901)'), findsOneWidget);
    expect(find.textContaining('kitsu 1'), findsOneWidget);
    expect(
      find.bySemanticsLabel('History-only records skipped'),
      findsOneWidget,
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Import 6 entries')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    await tester.tap(find.bySemanticsLabel('Import 6 entries'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Imported'), findsOneWidget);
    expect(find.bySemanticsLabel('Chapters marked read'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Choose backup file'), findsOneWidget);
  });

  testWidgets('a repeat import says it is already imported', (tester) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    for (var i = 0; i < 2; i++) {
      await c.pick();
      await c.runImport();
    }
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Already imported'), findsOneWidget);
  });

  testWidgets('a bad file shows the error and Try again resets', (
    tester,
  ) async {
    await _pump(tester, Uint8List.fromList([0x0A, 0x7F]));
    await tester.tap(find.bySemanticsLabel('Choose backup file'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Not a valid TachiyomiSY backup')),
      findsOneWidget,
    );
    expect(find.textContaining('Not a valid'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Try again'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Choose backup file'), findsOneWidget);
  });

  testWidgets('loading and importing states show progress', (tester) async {
    final gate = Completer<void>();
    final bytes = buildSyntheticTachibk();
    final fakes = Fakes();
    final writeGate = Completer<void>();
    fakes.library.gate = writeGate.future;
    final c = ImportController(
      picker: pickerOf(bytes),
      importer: fakes.importer,
      planner: (b) async {
        await gate.future;
        return planBackupSync(b);
      },
    );
    await tester.pumpWidget(MaterialApp(home: ImportScreen(controller: c)));
    final pending = c.pick();
    await tester.pump();
    expect(find.text('sy.tachibk'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.complete();
    await pending;
    await tester.pump();
    final run = c.runImport();
    await tester.pump();
    expect(find.text('0 / 6'), findsOneWidget);
    expect(find.bySemanticsLabel('Imported 0 of 6 entries'), findsOneWidget);
    writeGate.complete();
    await run;
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Imported'), findsOneWidget);
  });

  testWidgets('choose another file from the preview', (tester) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    await c.pick();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Choose another file'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Import 6 entries'), findsOneWidget);
    expect(find.text('6'), findsWidgets);
  });

  testWidgets('warns when tracker links cannot be stored', (tester) async {
    final controller = ImportController(
      picker: pickerOf(buildSyntheticTachibk()),
      importer: BackupImporter(
        library: FakeLibrary(),
        categories: FakeCategories(),
        progress: FakeProgress(),
      ),
      planner: (b) async => planBackupSync(b),
    );
    await tester.pumpWidget(
      MaterialApp(home: ImportScreen(controller: controller)),
    );
    await controller.pick();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link_off), findsOneWidget);
  });

  testWidgets('summary hides optional lines when they are zero', (
    tester,
  ) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    await c.pick();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Duplicates skipped'), findsNothing);
  });

  testWidgets('duplicates and an unnamed unavailable source', (tester) async {
    const summary = ImportSummary(
      entries: 1,
      categories: 0,
      memberships: 0,
      chaptersRead: 0,
      trackersByService: {},
      trackersImported: 0,
      notInLibrary: 0,
      duplicates: 2,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImportPreview(
            summary,
            unavailable: [UnavailableSource('', '42', 3)],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Duplicates skipped'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.bySemanticsLabel('3 entries'), findsOneWidget);
    expect(find.text('anilist 0 · mal 0 · mangaupdates 0'), findsOneWidget);
  });
}
