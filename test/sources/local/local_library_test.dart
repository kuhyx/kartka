import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/local_library.dart';

import 'fakes.dart';
import 'zip_builder.dart';

void main() {
  late MemoryBlobStore blobs;
  late MemoryKeyValueStore kv;
  late LocalLibrary lib;
  var now = DateTime.utc(2026, 10, 24);

  setUp(() {
    blobs = MemoryBlobStore();
    kv = MemoryKeyValueStore();
    now = DateTime.utc(2026, 10, 24);
    lib = LocalLibrary(blobs: blobs, kv: kv, clock: () => now);
  });

  List<int> cbz(String series, String number, List<String> pages) => buildZip({
    'ComicInfo.xml': comicInfoXml(series: series, number: number),
    for (final p in pages) p: null,
  });

  test('imports CBZs into BlobStore, grouped by series', () async {
    final report = await lib.importFiles([
      picked('bl-2.cbz', cbz('Blue Lock', '2', ['p10.jpg', 'p2.jpg'])),
      picked('bl-1.cbz', cbz('Blue Lock', '1', ['a.png'])),
      picked('broken.cbz', [1, 2, 3]),
      picked('notes.txt', [1]),
    ]);
    expect(report.chapters, 2);
    expect(report.mangaUrls, {'blue lock'});
    expect(report.errors.single, contains('broken.cbz'));

    final index = await lib.load();
    final m = index.manga.single;
    expect(m.chapters.map((c) => c.number), [1, 2]);
    final pages = m.chapters[1].pageBlobKeys;
    expect(pages, hasLength(2));
    expect(pages.every(isValidBlobKey), isTrue);
    expect(pages.every((k) => k.startsWith('local/')), isTrue);
    expect(utf8.decode((await blobs.get(pages[0]))!), 'p2.jpg');
    expect(utf8.decode((await blobs.get(pages[1]))!), 'p10.jpg');
    expect(await kv.get(LocalLibrary.indexKey), isNotNull);
  });

  test('imports a picked folder of images (web relative paths)', () async {
    await lib.importFiles([
      picked('2.jpg', utf8.encode('two'), relativePath: 'Saga/Ch 1/2.jpg'),
      picked('10.jpg', utf8.encode('ten'), relativePath: 'Saga/Ch 1/10.jpg'),
      picked('c.cbz', cbz('Saga', '2', ['x.jpg']), relativePath: 'Saga/c.cbz'),
      picked(
        'ComicInfo.xml',
        comicInfoXml(series: 'Saga', title: 'Prologue'),
        relativePath: 'Saga/Ch 0/ComicInfo.xml',
      ),
      picked('1.jpg', [0], relativePath: 'Saga/Ch 0/1.jpg'),
    ]);
    final m = (await lib.load()).find('saga')!;
    expect(m.chapters.map((c) => c.title), ['c', 'Prologue', 'Ch 1']);
    final folderPages = m.chapters[2].pageBlobKeys;
    expect(
      [for (final k in folderPages) utf8.decode((await blobs.get(k))!)],
      ['two', 'ten'],
    );
  });

  test('a failing read is reported, not thrown', () async {
    final report = await lib.importFiles([
      PickedFile(name: 'x.cbz', read: () async => throw StateError('gone')),
      PickedFile(
        name: '1.jpg',
        relativePath: 'F/1.jpg',
        read: () async => throw StateError('gone'),
      ),
    ]);
    expect(report.chapters, 0);
    expect(report.errors, hasLength(2));
  });

  test('re-import replaces pages and deletes orphaned blobs', () async {
    await lib.importFiles([
      picked('s.cbz', cbz('S', '1', ['1.jpg', '2.jpg'])),
    ]);
    now = now.add(const Duration(minutes: 1));
    await lib.importFiles([
      picked('s.cbz', cbz('S', '1', ['1.jpg'])),
    ]);
    final keys = await blobs.list('');
    expect(keys, hasLength(1));
    expect((await lib.load()).manga.single.chapters.single.pageBlobKeys, keys);
  });

  test('remove deletes the manga and its blobs', () async {
    await lib.importFiles([
      picked('s.cbz', cbz('S', '1', ['1.jpg'])),
    ]);
    await lib.remove('s');
    expect(await blobs.list(''), isEmpty);
    expect((await lib.load()).manga, isEmpty);
  });

  test('index persists across instances and changes are broadcast', () async {
    final seen = <int>[];
    final sub = lib.changes.listen((i) => seen.add(i.manga.length));
    await lib.importFiles([
      picked('s.cbz', cbz('S', '1', ['1.jpg'])),
    ]);
    final again = LocalLibrary(blobs: blobs, kv: kv);
    expect((await again.load()).manga.single.title, 'S');
    await sub.cancel();
    expect(seen, [1]);
  });

  test('concurrent imports are serialised and both land', () async {
    await Future.wait([
      lib.importFiles([
        picked('a.cbz', cbz('A', '1', ['1.jpg'])),
      ]),
      lib.importFiles([
        picked('b.cbz', cbz('B', '1', ['1.jpg'])),
      ]),
    ]);
    expect((await lib.load()).manga.map((m) => m.title), ['A', 'B']);
  });

  test('a failed import step does not wedge the queue', () async {
    final failing = LocalLibrary(blobs: _ThrowingBlobs(), kv: kv);
    await expectLater(
      failing.importFiles([
        picked('a.cbz', cbz('A', '1', ['1.jpg'])),
      ]),
      throwsStateError,
    );
    final ok = await failing.importFiles(const []);
    expect(ok.chapters, 0);
    expect(ok.summary, 'Nothing to import');
  });

  test('ImportReport.summary', () {
    expect(
      const ImportReport(
        chapters: 3,
        mangaUrls: {'a', 'b'},
        errors: [],
      ).summary,
      'Imported 3 chapters into 2 manga',
    );
    expect(
      const ImportReport(chapters: 1, mangaUrls: {'a'}, errors: ['x']).summary,
      'Imported 1 chapter into 1 manga, 1 failed',
    );
  });
}

class _ThrowingBlobs extends MemoryBlobStore {
  @override
  Future<void> put(String key, Uint8List bytes) async =>
      throw StateError('disk full');
}
