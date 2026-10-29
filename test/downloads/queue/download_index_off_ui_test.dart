import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/queue/download_index.dart';

void main() {
  final at = DateTime.utc(2026, 10, 29);
  String index(int n) {
    final idx = DownloadIndex();
    for (var i = 0; i < n; i++) {
      idx.put(
        'm|${i % 50}',
        OfflineChapter(
          chapter: ChapterInfo(url: '/c$i', name: 'Chapter $i', number: 1),
          pageCount: 20,
          bytes: i,
          downloadedAt: at,
        ),
      );
    }
    return idx.encode();
  }

  test('a large index decodes off the UI isolate, a small one inline', () {
    final big = index(2000);
    expect(big.length, greaterThan(downloadIndexOffUiChars));
    expect(index(3).length, lessThan(downloadIndexOffUiChars));
    return Future(() async {
      final off = await loadDownloadIndex(big);
      expect(off.totalBytes, DownloadIndex.decode(big).totalBytes);
      expect(off.chapter('m|7', '/c1957')?.pageCount, 20);
      expect((await loadDownloadIndex(index(3))).mangaKeys, hasLength(3));
      expect((await loadDownloadIndex(null)).mangaKeys, isEmpty);
    });
  });
}
