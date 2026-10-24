import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/import_local_tile.dart';
import 'package:kartka/sources/local/local_library.dart';

import 'fakes.dart';
import 'zip_builder.dart';

void main() {
  late FakeFilePicker picker;
  late LocalLibrary library;

  setUp(() => picker = FakeFilePicker());

  // The library is built inside the test body: futures created in setUp
  // belong to the real zone and never complete under the widget tester's
  // fake async, which would hang pumpAndSettle on the spinner.
  Future<void> pump(WidgetTester tester, {BlobStore? blobs}) {
    library = LocalLibrary(
      blobs: blobs ?? MemoryBlobStore(),
      kv: MemoryKeyValueStore(),
    );
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportLocalTile(library: library, picker: picker),
        ),
      ),
    );
  }

  Future<void> choose(WidgetTester tester, String option) async {
    await tester.tap(find.text('Import local files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  final cbz = buildZip({
    'ComicInfo.xml': comicInfoXml(series: 'Saga', number: '1'),
    '1.jpg': tinyPng,
  });

  testWidgets('archives: picks cbz/zip and reports the import', (t) async {
    picker = FakeFilePicker(files: [picked('saga.cbz', cbz)]);
    await pump(t);
    await choose(t, 'CBZ / ZIP archives');
    expect(picker.lastExtensions, ['cbz', 'zip']);
    expect(find.text('Imported 1 chapter into 1 manga'), findsOneWidget);
    expect((await library.load()).manga.single.title, 'Saga');
  });

  testWidgets('folder: picks a directory', (t) async {
    picker = FakeFilePicker(
      directory: [picked('1.jpg', tinyPng, relativePath: 'Saga/Ch 1/1.jpg')],
    );
    await pump(t);
    await choose(t, 'Folder of images');
    expect(picker.lastExtensions, isNull);
    expect(find.text('Imported 1 chapter into 1 manga'), findsOneWidget);
  });

  testWidgets('cancelled pick does nothing', (t) async {
    await pump(t);
    await choose(t, 'Folder of images');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('dismissing the chooser does nothing', (t) async {
    await pump(t);
    await t.tap(find.text('Import local files'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(picker.lastExtensions, isNull);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('unreadable files show an error', (t) async {
    picker = FakeFilePicker(
      files: [
        picked('bad.cbz', [1, 2, 3]),
      ],
    );
    await pump(t);
    await choose(t, 'CBZ / ZIP archives');
    expect(find.textContaining('1 failed'), findsOneWidget);
  });

  testWidgets('storage failure shows an error and re-enables', (t) async {
    picker = FakeFilePicker(files: [picked('saga.cbz', cbz)]);
    await pump(t, blobs: _FullBlobs());
    await choose(t, 'CBZ / ZIP archives');
    expect(find.textContaining('Import failed'), findsOneWidget);
    final tile = t.widget<ListTile>(find.byType(ListTile));
    expect(tile.enabled, isTrue);
  });

  testWidgets('shows progress and disables the tile meanwhile', (t) async {
    final gate = Completer<Uint8List>();
    picker = FakeFilePicker(
      files: [PickedFile(name: 'saga.cbz', read: () => gate.future)],
    );
    await pump(t);
    await t.tap(find.text('Import local files'));
    await t.pumpAndSettle();
    await t.tap(find.text('CBZ / ZIP archives'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(t.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
    gate.complete(cbz);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Imported 1 chapter into 1 manga'), findsOneWidget);
  });
}

class _FullBlobs extends MemoryBlobStore {
  @override
  Future<void> put(String key, Uint8List bytes) async =>
      throw StateError('disk full');
}
