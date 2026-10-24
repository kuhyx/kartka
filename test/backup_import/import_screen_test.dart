import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/import_controller.dart';
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
    expect(find.text('Import SY backup'), findsOneWidget);
    expect(find.text('Choose backup file'), findsOneWidget);

    await tester.tap(find.text('Choose backup file'));
    await tester.pumpAndSettle();
    expect(find.text('sy.tachibk'), findsOneWidget);
    expect(find.text('Library entries'), findsOneWidget);
    expect(find.text('Chapters read'), findsOneWidget);
    expect(find.text('AniList links'), findsOneWidget);
    expect(find.text('Source unavailable'), findsOneWidget);
    expect(find.text('E-Hentai (6901)'), findsOneWidget);
    expect(find.textContaining('mangaupdates 1'), findsOneWidget);
    expect(find.text('History-only records skipped'), findsOneWidget);

    await tester.tap(find.text('Import 6 entries'));
    await tester.pumpAndSettle();
    expect(find.text('Imported'), findsOneWidget);
    expect(find.text('Chapters marked read'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Choose backup file'), findsOneWidget);
  });

  testWidgets('a repeat import says it is already imported', (tester) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    for (var i = 0; i < 2; i++) {
      await c.pick();
      await c.runImport();
    }
    await tester.pumpAndSettle();
    expect(find.text('Already imported'), findsOneWidget);
  });

  testWidgets('a bad file shows the error and Try again resets', (
    tester,
  ) async {
    await _pump(tester, Uint8List.fromList([0x0A, 0x7F]));
    await tester.tap(find.text('Choose backup file'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Not a valid TachiyomiSY backup'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Choose backup file'), findsOneWidget);
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
    expect(find.text('Reading sy.tachibk'), findsOneWidget);
    gate.complete();
    await pending;
    await tester.pump();
    final run = c.runImport();
    await tester.pump();
    expect(find.text('Imported 0 of 6 entries'), findsOneWidget);
    writeGate.complete();
    await run;
    await tester.pumpAndSettle();
    expect(find.text('Imported'), findsOneWidget);
  });

  testWidgets('choose another file from the preview', (tester) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    await c.pick();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose another file'));
    await tester.pumpAndSettle();
    expect(find.text('Import 6 entries'), findsOneWidget);
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
    expect(find.textContaining('Tracking is not installed'), findsOneWidget);
  });

  testWidgets('summary hides optional lines when they are zero', (
    tester,
  ) async {
    final c = await _pump(tester, buildSyntheticTachibk());
    await c.pick();
    await tester.pumpAndSettle();
    expect(find.text('Duplicates skipped'), findsNothing);
  });
}
