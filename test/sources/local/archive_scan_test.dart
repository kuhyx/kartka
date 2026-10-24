import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/local/archive_scan.dart';
import 'package:kartka/sources/local/comic_info.dart';

import 'zip_builder.dart';

List<String> _names(ScannedChapter c) => [
  for (final p in c.pages) utf8.decode(p),
];

void main() {
  group('scanArchive', () {
    test('keeps images in natural order, skipping junk', () {
      final zip = buildZip({
        'page10.jpg': null,
        'page2.JPG': null,
        'page1.png': null,
        'credits.txt': null,
        'sub/': null,
        '__MACOSX/._page1.png': null,
        '._page3.jpg': null,
        '.hidden/page0.jpg': null,
      });
      final c = scanArchive('My Series/Chapter 3.cbz', zip);
      expect(_names(c), ['page1.png', 'page2.JPG', 'page10.jpg']);
      expect(c.name, 'Chapter 3');
      expect(c.folder, 'My Series');
      expect(c.info, isNull);
      expect(c.seriesTitle, 'My Series');
      expect(c.chapterTitle, 'Chapter 3');
    });

    test('sorts across nested directories by full path', () {
      final zip = buildZip({
        'v1/c10/01.webp': null,
        'v1/c2/02.webp': null,
        'v1/c2/01.webp': null,
      });
      expect(_names(scanArchive('a.zip', zip)), [
        'v1/c2/01.webp',
        'v1/c2/02.webp',
        'v1/c10/01.webp',
      ]);
    });

    test('reads ComicInfo.xml in any case at any depth', () {
      final zip = buildZip({
        'inner/comicinfo.xml': comicInfoXml(
          series: 'Blue Lock',
          number: '2',
          title: 'Two',
        ),
        '001.jpg': null,
      });
      final c = scanArchive(r'C:\dl\blue-lock-002.cbz', zip);
      expect(
        c.info,
        const ComicInfo(series: 'Blue Lock', number: 2, title: 'Two'),
      );
      expect(c.seriesTitle, 'Blue Lock');
      expect(c.chapterTitle, 'Two');
      expect(c.name, 'blue-lock-002');
      expect(c.folder, 'dl');
    });

    test('series falls back to the file stem without a folder', () {
      final c = scanArchive('Solo.cbz', buildZip({'1.jpg': null}));
      expect(c.folder, isNull);
      expect(c.seriesTitle, 'Solo');
    });

    test('corrupt bytes raise LocalImportException', () {
      expect(
        () => scanArchive('bad.cbz', Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<LocalImportException>()),
      );
      expect(
        () => scanArchive('empty.cbz', Uint8List(0)),
        throwsA(isA<LocalImportException>()),
      );
      // Incompressible-ish data, so the deflate stream itself gets corrupted.
      final data = [for (var i = 0; i < 20000; i++) (i * 7919) % 251 ^ i ~/ 13];
      final valid = buildZip({'1.jpg': data});
      final truncated = Uint8List.sublistView(valid, 0, valid.length - 30);
      final garbled = Uint8List.fromList(valid);
      for (var i = 36; i < 40; i++) {
        garbled[i] ^= 0x5a;
      }
      for (final bad in [truncated, garbled]) {
        expect(
          () => scanArchive('bad.cbz', bad),
          throwsA(isA<LocalImportException>()),
        );
      }
    });

    test('an archive without images is rejected', () {
      expect(
        () => scanArchive('text.cbz', buildZip({'readme.txt': null})),
        throwsA(
          isA<LocalImportException>().having(
            (e) => e.toString(),
            'message',
            contains('text.cbz'),
          ),
        ),
      );
    });
  });

  group('path helpers', () {
    test('isImagePath', () {
      expect(isImagePath('a/b.AVIF'), isTrue);
      expect(isImagePath('a/b.jpeg'), isTrue);
      expect(isImagePath('a/b.txt'), isFalse);
      expect(isImagePath('noext'), isFalse);
    });

    test('isJunkPath', () {
      expect(isJunkPath('__MACOSX/x.jpg'), isTrue);
      expect(isJunkPath('a/.DS_Store'), isTrue);
      expect(isJunkPath('a/Thumbs.db'), isTrue);
      expect(isJunkPath('a/b.jpg'), isFalse);
    });

    test('isArchivePath', () {
      expect(isArchivePath('x/Y.CBZ'), isTrue);
      expect(isArchivePath('y.zip'), isTrue);
      expect(isArchivePath('y.cbr'), isFalse);
    });

    test('stem, parent and dirname', () {
      expect(fileStem('a/b.c.cbz'), 'b.c');
      expect(fileStem('noext'), 'noext');
      expect(parentName('x/y/z.cbz'), 'y');
      expect(parentName('z.cbz'), isNull);
      expect(dirName('x/y/z.jpg'), 'x/y');
      expect(dirName('z.jpg'), '');
      expect(normalizePath(r'a\b\c.jpg'), 'a/b/c.jpg');
    });
  });
}
