import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/queue/download_index.dart';

void main() {
  final at = DateTime.utc(2026, 10, 24);
  OfflineChapter rec(String url, int bytes) => OfflineChapter(
    chapter: ChapterInfo(url: url, name: 'Ch $url', number: 2),
    pageCount: 3,
    bytes: bytes,
    downloadedAt: at,
  );

  test('put, lookup and usage per manga and in total', () {
    final idx = DownloadIndex()
      ..put('a|1', rec('/1', 100))
      ..put('a|1', rec('/2', 50))
      ..put('b|1', rec('/9', 7));
    expect(idx.chapter('a|1', '/2')?.bytes, 50);
    expect(idx.chapter('a|1', '/x'), isNull);
    expect(idx.chapter('zz', '/x'), isNull);
    expect(idx.mangaBytes('a|1'), 150);
    expect(idx.mangaBytes('none'), 0);
    expect(idx.totalBytes, 157);
    expect(idx.mangaKeys, ['a|1', 'b|1']);
    expect(idx.chapters('a|1').map((c) => c.chapterUrl), ['/1', '/2']);
    expect(idx.chapters('none'), isEmpty);
  });

  test(
    'remove chapter drops empty manga; removeManga returns its chapters',
    () {
      final idx = DownloadIndex()
        ..put('a|1', rec('/1', 1))
        ..put('b|1', rec('/1', 1))
        ..put('b|1', rec('/2', 1));
      expect(idx.removeChapter('a|1', '/1')?.chapterUrl, '/1');
      expect(idx.removeChapter('a|1', '/1'), isNull);
      expect(idx.mangaKeys, ['b|1']);
      expect(idx.removeManga('b|1').length, 2);
      expect(idx.removeManga('b|1'), isEmpty);
      expect(idx.totalBytes, 0);
    },
  );

  test('encode/decode round-trip, null decodes empty', () {
    final idx = DownloadIndex()..put('a|1', rec('/1', 10));
    final back = DownloadIndex.decode(idx.encode());
    expect(back.chapter('a|1', '/1'), rec('/1', 10));
    expect(rec('/1', 10).hashCode, back.chapter('a|1', '/1').hashCode);
    expect(rec('/1', 10), isNot(rec('/1', 11)));
    expect(back.chapter('a|1', '/1')?.chapter.number, 2);
    expect(back.chapter('a|1', '/1')?.chapterName, 'Ch /1');
    expect(DownloadIndex.decode(null).totalBytes, 0);
  });
}
