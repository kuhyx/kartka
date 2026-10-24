import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/local/comic_info.dart';

String _fixture(String name) =>
    File('test/fixtures/local/$name').readAsStringSync();

void main() {
  group('ComicInfo.parse', () {
    test('reads title, series and a fractional number despite BOM + ns', () {
      final bytes = File('test/fixtures/local/comicinfo_full.xml')
          .readAsBytesSync();
      final info = ComicInfo.parseBytes(bytes);
      expect(info, isNotNull);
      expect(info!.title, 'The Beginning');
      expect(info.series, 'Blue   Lock');
      expect(info.number, 1.5);
    });

    test('non-numeric Number becomes null and empty Title is null', () {
      final info = ComicInfo.parse(_fixture('comicinfo_extra.xml'))!;
      expect(info.series, 'Blue Lock');
      expect(info.number, isNull);
      expect(info.title, isNull);
    });

    test('malformed XML yields null', () {
      expect(ComicInfo.parse(_fixture('comicinfo_malformed.xml')), isNull);
    });

    test('a non-ComicInfo root yields null', () {
      expect(ComicInfo.parse(_fixture('not_comicinfo.xml')), isNull);
    });

    test('invalid UTF-8 bytes are tolerated', () {
      final bytes = [
        ...utf8.encode('<ComicInfo><Series>A'),
        0xff,
        ...utf8.encode('</Series></ComicInfo>'),
      ];
      expect(ComicInfo.parseBytes(bytes)!.series, startsWith('A'));
    });

    test('comma decimals and padded numbers parse', () {
      expect(
        ComicInfo.parse('<ComicInfo><Number> 3,25 </Number></ComicInfo>')!
            .number,
        3.25,
      );
      expect(
        ComicInfo.parse('<ComicInfo><Number>12</Number></ComicInfo>')!.number,
        12,
      );
    });

    test('value equality', () {
      const a = ComicInfo(title: 't', series: 's', number: 1);
      expect(a, const ComicInfo(title: 't', series: 's', number: 1));
      expect(
        a.hashCode,
        const ComicInfo(title: 't', series: 's', number: 1).hashCode,
      );
      expect(a == const ComicInfo(series: 's', number: 1), isFalse);
      expect(a.toString(), contains('s'));
    });
  });

  group('isComicInfoPath', () {
    test('matches any case at any depth', () {
      expect(isComicInfoPath('ComicInfo.xml'), isTrue);
      expect(isComicInfoPath('vol1/comicinfo.XML'), isTrue);
      expect(isComicInfoPath('vol1/notcomicinfo.xml'), isFalse);
      expect(isComicInfoPath('ComicInfo.xml.bak'), isFalse);
    });
  });
}
