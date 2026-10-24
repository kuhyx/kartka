import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/local/archive_scan.dart';
import 'package:kartka/sources/local/comic_info.dart';
import 'package:kartka/sources/local/local_index.dart';

ScannedChapter _ch(String name, {String? folder, ComicInfo? info}) =>
    ScannedChapter(
      name: name,
      folder: folder,
      info: info,
      pages: [Uint8List(1)],
    );

List<String> _keys(String url, int n) => [
  for (var i = 0; i < n; i++) '$url#$i',
];

void main() {
  final t0 = DateTime.utc(2026, 10, 24);
  final t1 = t0.add(const Duration(hours: 1));

  group('ids', () {
    test('seriesKey normalises case and whitespace', () {
      expect(seriesKey('  Blue   LOCK '), 'blue lock');
    });

    test('chapterUrlFor is content-derived and stable', () {
      final c = _ch('Ch 02', folder: 'Blue Lock');
      expect(chapterUrlFor(c), 'blue lock/ch 02');
    });
  });

  group('LocalIndex.add', () {
    test('groups chapters of one series into one manga, ordered', () {
      const info3 = ComicInfo(series: 'Blue Lock', number: 3, title: 'Three');
      const info1 = ComicInfo(series: 'blue  lock', number: 1);
      var index = const LocalIndex.empty();
      for (final (c, t) in [
        (_ch('c3', info: info3), t0),
        (_ch('c1', info: info1), t0),
        (_ch('extra', folder: 'Blue Lock'), t1),
        (_ch('c1.5', info: const ComicInfo(series: 'Blue Lock')), t1),
      ]) {
        index = index.add(c, _keys(chapterUrlFor(c), 2), t).index;
      }
      expect(index.manga, hasLength(1));
      final m = index.manga.single;
      expect(m.url, 'blue lock');
      expect(m.title, 'Blue Lock');
      expect(m.updatedAt, t1);
      expect(m.chapters.map((c) => c.title), ['c1', 'Three', 'c1.5', 'extra']);
      expect(m.chapters[1].number, 3);
      expect(m.coverBlobKey, 'blue lock/c1#0');
    });

    test('different series stay separate manga', () {
      final index = const LocalIndex.empty()
          .add(_ch('a'), ['a#0'], t0)
          .index
          .add(_ch('b'), ['b#0'], t1)
          .index;
      expect(index.manga.map((m) => m.title), ['a', 'b']);
      expect(index.find('a')!.chapters.single.pageBlobKeys, ['a#0']);
      expect(index.find('zzz'), isNull);
      expect(index.findChapter('b/b')!.title, 'b');
      expect(index.findChapter('a/zzz'), isNull);
      expect(index.findChapter('zzz/b'), isNull);
    });

    test('re-importing a chapter replaces it and reports orphan blobs', () {
      final first = const LocalIndex.empty().add(_ch('x'), ['k0', 'k1'], t0);
      expect(first.orphanBlobKeys, isEmpty);
      final again = first.index.add(_ch('x'), ['k0'], t1);
      expect(again.orphanBlobKeys, ['k1']);
      expect(again.index.manga.single.chapters.single.pageBlobKeys, ['k0']);
      expect(again.index.manga.single.chapters.single.importedAt, t1);
    });
  });

  group('LocalIndex.remove', () {
    test('drops a manga and returns its blob keys', () {
      final index = const LocalIndex.empty().add(_ch('x'), ['k0'], t0).index;
      final removed = index.remove('x');
      expect(removed.index.manga, isEmpty);
      expect(removed.orphanBlobKeys, ['k0']);
      expect(index.remove('missing').orphanBlobKeys, isEmpty);
    });
  });

  group('JSON', () {
    test('round-trips through a JSON string', () {
      const info = ComicInfo(series: 'S', number: 2.5, title: 'T');
      final index = const LocalIndex.empty()
          .add(_ch('c', info: info), ['k0', 'k1'], t0)
          .index
          .add(_ch('d', folder: 'S'), ['k2'], t1)
          .index;
      final decoded = LocalIndex.decode(jsonEncode(index.toJson()));
      expect(decoded, index);
      expect(decoded.hashCode, index.hashCode);
    });

    test('missing or garbled JSON decodes to an empty index', () {
      expect(LocalIndex.decode(null).manga, isEmpty);
      expect(LocalIndex.decode('not json').manga, isEmpty);
      expect(LocalIndex.decode('[1]').manga, isEmpty);
      expect(LocalIndex.decode('{"v":1,"manga":[{"url":3}]}').manga, isEmpty);
    });
  });
}
