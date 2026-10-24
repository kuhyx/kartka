import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/local/import_local_tile.dart';
import 'package:kartka/sources/local/local_library.dart';

import 'fakes.dart';
import 'zip_builder.dart';

void main() {
  late FakePicker picker;
  late LocalLibrary library;

  setUp(() {
    picker = FakePicker();
    library = LocalLibrary(blobs: MemoryBlobs(), kv: MemoryKv());
  });

  Future<void> pump(WidgetTester tester, {LocalLibrary? lib}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportLocalTile(library: lib ?? library, picker: picker),
          ),
        ),
      );

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
    picker.files = [picked('saga.cbz', cbz)];
    await pump(t);
    await choose(t, 'CBZ / ZIP archives');
    expect(picker.calls, ['files:cbz,zip:true']);
    expect(find.text('Imported 1 chapter into 1 manga'), findsOneWidget);
    expect((await library.load()).manga.single.title, 'Saga');
  });

  testWidgets('folder: picks a directory', (t) async {
    picker.directory = [
      picked('1.jpg', tinyPng, relativePath: 'Saga/Ch 1/1.jpg'),
    ];
    await pump(t);
    await choose(t, 'Folder of images');
    expect(picker.calls, ['directory']);
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
    expect(picker.calls, isEmpty);
  });

  testWidgets('unreadable files show an error', (t) async {
    picker.files = [
      picked('bad.cbz', [1, 2, 3]),
    ];
    await pump(t);
    await choose(t, 'CBZ / ZIP archives');
    expect(find.textContaining('1 failed'), findsOneWidget);
  });

  testWidgets('storage failure shows an error and re-enables', (t) async {
    picker.files = [picked('saga.cbz', cbz)];
    final broken = LocalLibrary(blobs: _FullBlobs(), kv: MemoryKv());
    await pump(t, lib: broken);
    await choose(t, 'CBZ / ZIP archives');
    expect(find.textContaining('Import failed'), findsOneWidget);
    final tile = t.widget<ListTile>(find.byType(ListTile));
    expect(tile.enabled, isTrue);
  });

  testWidgets('shows progress while importing', (t) async {
    picker.files = [picked('saga.cbz', cbz)];
    await pump(t);
    await t.tap(find.text('Import local files'));
    await t.pumpAndSettle();
    await t.tap(find.text('CBZ / ZIP archives'));
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _FullBlobs extends MemoryBlobs {
  @override
  Future<void> put(String key, Uint8List bytes) async =>
      throw StateError('disk full');
}
