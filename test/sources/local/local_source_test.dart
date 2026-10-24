import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/local_library.dart';
import 'package:kartka/sources/local/local_source.dart';

import 'fakes.dart';
import 'zip_builder.dart';

void main() {
  late LocalLibrary lib;
  late LocalSource source;
  var now = DateTime.utc(2026, 10, 24);

  List<int> cbz(String series, String number, {String? title}) => buildZip({
    'ComicInfo.xml': comicInfoXml(series: series, number: number, title: title),
    'p2.jpg': null,
    'p1.jpg': null,
  });

  setUp(() async {
    now = DateTime.utc(2026, 10, 24);
    lib = LocalLibrary(
      blobs: MemoryBlobStore(),
      kv: MemoryKeyValueStore(),
      clock: () => now,
    );
    source = LocalSource(lib);
    await lib.importFiles([
      picked('bl1.cbz', cbz('Blue Lock', '1', title: 'Start')),
      picked('bl2.cbz', cbz('Blue Lock', '2')),
    ]);
    now = now.add(const Duration(days: 1));
    await lib.importFiles([picked('a.cbz', cbz('Akira', '1'))]);
  });

  test('ref is the local source', () {
    expect(source.ref.id, 'local');
    expect(source.ref.origin, SourceOrigin.local);
  });

  test('popular lists every manga by title with a blob cover', () async {
    final page = await source.popular(1);
    expect(page.hasNext, isFalse);
    expect(page.items.map((m) => m.title), ['Akira', 'Blue Lock']);
    final bl = page.items[1];
    expect(bl.sourceId, 'local');
    expect(bl.url, 'blue lock');
    expect(bl.coverUrl, startsWith('$kartkaBlobScheme://local/'));
    expect((await source.popular(2)).items, isEmpty);
  });

  test('latest orders by last import, newest first', () async {
    final page = await source.latest(1);
    expect(page.items.map((m) => m.title), ['Akira', 'Blue Lock']);
    expect((await source.latest(2)).items, isEmpty);
  });

  test('search matches titles case- and space-insensitively', () async {
    final page = await source.search('  BLUE   l', 1);
    expect(page.items.map((m) => m.title), ['Blue Lock']);
    expect((await source.search('zzz', 1)).items, isEmpty);
    expect((await source.search('blue', 2)).items, isEmpty);
  });

  test('details describe the local manga', () async {
    final d = await source.details('blue lock');
    expect(d.title, 'Blue Lock');
    expect(d.status, MangaStatus.unknown);
    expect(d.description, '2 chapters imported on this device');
    expect(d.coverUrl, isNotNull);
  });

  test('chapters are newest first with numbers and import time', () async {
    final chapters = await source.chapters('blue lock');
    expect(chapters.map((c) => c.name), ['bl2', 'Start']);
    expect(chapters.map((c) => c.number), [2, 1]);
    expect(chapters.last.url, 'blue lock/bl1');
    expect(chapters.last.uploadedAt, DateTime.utc(2026, 10, 24));
  });

  test('pages point at BlobStore pages in natural order', () async {
    final pages = await source.pages('blue lock/bl1');
    expect(pages.map((p) => p.index), [0, 1]);
    expect(pages.every((p) => p.headers.isEmpty), isTrue);
    expect(
      pages.every((p) => p.imageUrl.startsWith('$kartkaBlobScheme://')),
      isTrue,
    );
  });

  test('unknown manga or chapter throws LocalNotImportedException', () {
    expect(
      () => source.details('nope'),
      throwsA(isA<LocalNotImportedException>()),
    );
    expect(
      () => source.chapters('nope'),
      throwsA(isA<LocalNotImportedException>()),
    );
    expect(
      () => source.pages('blue lock/nope'),
      throwsA(
        isA<LocalNotImportedException>().having(
          (e) => e.toString(),
          'message',
          contains('blue lock/nope'),
        ),
      ),
    );
  });
}
