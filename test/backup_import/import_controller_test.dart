import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/import_controller.dart';
import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';

import 'fake_setup.dart';
import 'fixture_builder.dart';

PickedFile _file(String name, Uint8List bytes) =>
    PickedFile(name: name, read: () async => bytes);

void main() {
  late Fakes f;

  ImportController make(List<PickedFile> files, [FakeFilePicker? out]) =>
      ImportController(
        picker: out ?? FakeFilePicker(files: files),
        importer: f.importer,
      );

  setUp(() => f = Fakes());

  test('pick, preview, import, done', () async {
    final picker = FakeFilePicker(
      files: [_file('b.tachibk', buildSyntheticTachibk())],
    );
    final c = make([], picker);
    expect(c.phase, ImportPhase.idle);
    final phases = <ImportPhase>[];
    c.addListener(() => phases.add(c.phase));
    await c.pick();
    expect(picker.lastExtensions, ['tachibk']);
    expect(c.phase, ImportPhase.preview);
    expect(c.fileName, 'b.tachibk');
    expect(c.plan!.summary.entries, 6);
    expect(f.library.entries, isEmpty, reason: 'dry run writes nothing');
    await c.runImport();
    expect(c.phase, ImportPhase.done);
    expect(c.result!.entries, 6);
    expect(c.progress, (6, 6));
    expect(phases.first, ImportPhase.loading);
    expect(phases, contains(ImportPhase.preview));
    expect(phases, contains(ImportPhase.importing));
    expect(phases.last, ImportPhase.done);
  });

  test('cancelling the picker stays idle', () async {
    final c = make([]);
    await c.pick();
    expect(c.phase, ImportPhase.idle);
  });

  test('a bad file fails with a message and can be retried', () async {
    final c = make([
      _file('x.tachibk', Uint8List.fromList([0x0A, 0x7F])),
    ]);
    await c.pick();
    expect(c.phase, ImportPhase.failed);
    expect(c.error, contains('Not a valid TachiyomiSY backup'));
    c.reset();
    expect(c.phase, ImportPhase.idle);
    expect(c.error, isNull);
  });

  test('importing twice reports nothing new', () async {
    final bytes = buildSyntheticTachibk();
    final c = make([_file('b.tachibk', bytes)]);
    await c.pick();
    await c.runImport();
    await c.pick();
    await c.runImport();
    expect(c.result!.changedNothing, isTrue);
  });

  test('runImport without a plan is a no-op', () async {
    final c = make([]);
    await c.runImport();
    expect(c.phase, ImportPhase.idle);
  });

  test('a repository failure becomes a failed state', () async {
    f.library.failOnWrite = true;
    final c = make([_file('b.tachibk', buildSyntheticTachibk())]);
    await c.pick();
    await c.runImport();
    expect(c.phase, ImportPhase.failed);
    expect(c.error, contains('disk full'));
  });
}
