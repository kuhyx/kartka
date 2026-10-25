import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/data/page_source.dart';

import '../support/fakes.dart';

void main() {
  const key = 'fake|/m/1';

  test('offline pages win and the source is never asked', () async {
    final source = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 3)});
    final offline = fakePages('/c/1', 2);
    final result = await loadChapterPages(
      key: key,
      chapterUrl: '/c/1',
      downloads: FakeDownloads({'/c/1': offline}),
      source: source,
    );
    expect(result.pages, offline);
    expect(result.offline, isTrue);
    expect(source.pageCalls, isEmpty);
  });

  test(
    'falls back to the source when not downloaded or no downloads',
    () async {
      final source = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 3)});
      for (final downloads in [FakeDownloads(), null]) {
        final result = await loadChapterPages(
          key: key,
          chapterUrl: '/c/1',
          downloads: downloads,
          source: source,
        );
        expect(result.pages, hasLength(3));
        expect(result.offline, isFalse);
      }
    },
  );

  test('empty offline list counts as not downloaded', () async {
    final source = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 1)});
    final result = await loadChapterPages(
      key: key,
      chapterUrl: '/c/1',
      downloads: FakeDownloads({'/c/1': const []}),
      source: source,
    );
    expect(result.offline, isFalse);
  });

  test('no download and no source is an error', () async {
    await expectLater(
      loadChapterPages(key: key, chapterUrl: '/c/1', downloads: null),
      throwsA(isA<ReaderLoadException>()),
    );
    expect(const ReaderLoadException('x').toString(), contains('x'));
  });

  test('pages are sorted by index', () async {
    final pages = fakePages('/c/1', 3).reversed.toList();
    final result = await loadChapterPages(
      key: key,
      chapterUrl: '/c/1',
      downloads: FakeDownloads({'/c/1': pages}),
    );
    expect(result.pages.map((p) => p.index), [0, 1, 2]);
  });

  test('the next chapter must have pages and answer in time', () async {
    final next = await loadNextChapterPages(
      key: key,
      chapterUrl: '/c/1',
      downloads: FakeDownloads({'/c/1': fakePages('/c/1', 2)}),
      timeout: const Duration(seconds: 1),
    );
    expect(next.pages, hasLength(2));
    await expectLater(
      loadNextChapterPages(
        key: key,
        chapterUrl: '/c/1',
        downloads: null,
        source: FakeSource(pageMap: {'/c/1': const []}),
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<ReaderLoadException>()),
    );
  });

  test('advance failures read as plain messages', () {
    expect(advanceFailureMessage(const ReaderLoadException('gone')), 'gone');
    expect(
      advanceFailureMessage(TimeoutException('x', const Duration(seconds: 30))),
      'Timed out after 30 s.',
    );
    expect(advanceFailureMessage(TimeoutException('x')), contains('?'));
    expect(advanceFailureMessage(StateError('boom')), contains('boom'));
  });
}
