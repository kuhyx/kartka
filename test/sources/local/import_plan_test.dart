import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/local/comic_info.dart';
import 'package:kartka/sources/local/import_plan.dart';

import 'zip_builder.dart';

void main() {
  group('planImport', () {
    test('archives become units; images group by directory', () {
      final plan = planImport([
        'Series/Ch 10/p1.jpg',
        'Series/Ch 2/p10.jpg',
        'Series/Ch 2/p2.jpg',
        'Series/Ch 2/ComicInfo.xml',
        'Series/Ch 2/notes.txt',
        'Series/__MACOSX/Ch 2/._p2.jpg',
        'Series/vol 1.cbz',
        'Other.ZIP',
      ]);
      expect(plan.map((u) => u.path), [
        'Other.ZIP',
        'Series/Ch 2',
        'Series/Ch 10',
        'Series/vol 1.cbz',
      ]);
      final ch2 = plan[1] as FolderUnit;
      expect(ch2.imagePaths, ['Series/Ch 2/p2.jpg', 'Series/Ch 2/p10.jpg']);
      expect(ch2.comicInfoPath, 'Series/Ch 2/ComicInfo.xml');
      expect((plan[2] as FolderUnit).comicInfoPath, isNull);
      expect(plan[0], isA<ArchiveUnit>());
    });

    test('a ComicInfo.xml alone does not make a chapter', () {
      expect(planImport(['a/ComicInfo.xml', 'a/readme.md']), isEmpty);
    });

    test('backslash paths are normalised', () {
      final plan = planImport([r'S\c1\1.png']);
      expect(plan.single.path, 'S/c1');
    });
  });

  group('scanFolder', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

    test('names the chapter after its folder and series after the parent', () {
      const unit = FolderUnit(
        path: 'Series/Ch 2',
        imagePaths: ['Series/Ch 2/1.jpg'],
      );
      final c = scanFolder(unit, [b('1')], null);
      expect(c.name, 'Ch 2');
      expect(c.folder, 'Series');
      expect(c.seriesTitle, 'Series');
      expect(c.pages.single, b('1'));
    });

    test('ComicInfo bytes override the folder names', () {
      const unit = FolderUnit(path: 'x', imagePaths: ['x/1.jpg']);
      final c = scanFolder(unit, [
        b('1'),
      ], Uint8List.fromList(comicInfoXml(series: 'Real', number: '4')));
      expect(c.info, const ComicInfo(series: 'Real', number: 4));
      expect(c.seriesTitle, 'Real');
      expect(c.folder, isNull);
    });

    test('top-level loose images get a placeholder name', () {
      const unit = FolderUnit(path: '', imagePaths: ['1.jpg']);
      expect(scanFolder(unit, [b('1')], null).name, looseImagesName);
    });
  });
}
