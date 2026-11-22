import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'ahead_fixture.dart';
import 'session_fixture.dart';

/// perf.slow reader.chapter (19643be5): the chapter-edge spinner waited on
/// the chapter list (fetched after page 1), then on the next chapter's page
/// list. A stored list names the next chapter at open, and a short chapter
/// no longer leaves the one after it unloaded.
void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());

  List<String> loaded(ReaderSession s) => [for (final g in s.segments) g.url];

  test('a stored list starts the next chapter before the fresh list', () async {
    final list = Completer<List<ChapterInfo>>();
    final src = GatedSource(
      list: list,
      pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
    );
    final s = f.make(source: src, stored: const StoredLists(sessionChapters));
    await s.open();
    await pumpEventQueue();
    expect(src.asked, ['/c/2', '/c/3']);
    expect(loaded(s), ['/c/2', '/c/3']);
    expect(s.previousChapter?.url, '/c/1');
    expect(s.previousLoading, isTrue, reason: 'the fresh list is still due');
  });

  test('the stored list stays when the fresh one lacks the chapter', () async {
    final list = Completer<List<ChapterInfo>>();
    final src = GatedSource(
      list: list,
      pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
    );
    final s = f.make(source: src, stored: const StoredLists(sessionChapters));
    await s.open();
    await pumpEventQueue();
    list.complete(const []);
    await pumpEventQueue();
    expect((s.previousChapter?.url, s.nextChapter), ('/c/1', null));
    expect(s.segments.last.neighbours.previous?.url, '/c/2');
  });

  test('a store that fails is no store', () async {
    final s = f.make(
      stored: StoredLists(sessionChapters, error: StateError('kv')),
    );
    await s.open();
    await pumpEventQueue();
    expect(s.nextChapter?.url, '/c/3');
  });

  test('a stored list without the chapter is ignored', () async {
    final list = Completer<List<ChapterInfo>>();
    final src = GatedSource(
      list: list,
      pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
    );
    final s = f.make(source: src, stored: StoredLists([sessionChapters.last]));
    await s.open();
    await pumpEventQueue();
    expect(src.asked, ['/c/2']);
    s.onItem(6);
    expect(s.nextLoading, isTrue);
    list.complete(sessionChapters);
    await pumpEventQueue();
    expect(loaded(s), ['/c/2', '/c/3']);
    expect((s.segment, s.page, s.onTrailing), (1, 0, false));
  });

  test('a stored list that ends here waits for the fresh one', () async {
    final list = Completer<List<ChapterInfo>>();
    final src = GatedSource(
      list: list,
      pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
    );
    final s = f.make(
      source: src,
      stored: StoredLists(sessionChapters.sublist(1)),
    );
    await s.open();
    await pumpEventQueue();
    s.onItem(6);
    expect(s.nextChapter, isNull);
    expect(s.nextLoading, isTrue, reason: 'a spinner, not the end icon');
    list.complete(sessionChapters);
    await pumpEventQueue();
    expect(loaded(s), ['/c/2', '/c/3']);
    expect((s.segment, s.onTrailing), (1, false));
  });

  group('the fresh list names another next chapter', () {
    late Completer<List<ChapterInfo>> list;
    late GatedSource src;
    setUp(() {
      list = Completer();
      src = GatedSource(
        list: list,
        pageMap: {
          '/c/2': fakePages('/c/2', 5),
          '/c/3': fakePages('/c/3', 3),
          '/c/2.5': fakePages('/c/2.5', 2),
        },
      );
    });

    test('a loaded one the reader has not reached is dropped', () async {
      final s = f.make(source: src, stored: const StoredLists(sessionChapters));
      await s.open();
      await pumpEventQueue();
      expect(loaded(s), ['/c/2', '/c/3']);
      list.complete(freshChapters);
      await pumpEventQueue();
      expect(loaded(s), ['/c/2', '/c/2.5']);
      expect(s.strip.pageCounts, [5, 2]);
      expect(s.nextChapter?.url, '/c/3');
    });

    test('one still loading is not added', () async {
      final gate = src.pageGates['/c/3'] = Completer();
      final s = f.make(source: src, stored: const StoredLists(sessionChapters));
      await s.open();
      await pumpEventQueue();
      list.complete(freshChapters);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(loaded(s), ['/c/2', '/c/2.5']);
    });

    test('one the reader is in stays', () async {
      final s = f.make(source: src, stored: const StoredLists(sessionChapters));
      await s.open();
      await pumpEventQueue();
      s.onItem(s.strip.itemForPage(0, segment: 1));
      list.complete(freshChapters);
      await pumpEventQueue();
      expect(loaded(s).take(2), ['/c/2', '/c/3']);
      expect(s.neighbours.previous?.url, '/c/2.5');
    });
  });

  test('a short next chapter does not stall the one after it', () async {
    const four = [
      ChapterInfo(url: '/c/4', name: 'Ch. 4', number: 4),
      ...sessionChapters,
    ];
    final src = GatedSource(
      chapterList: four,
      pageMap: {
        '/c/2': fakePages('/c/2', 5),
        '/c/3': fakePages('/c/3', 2),
        '/c/4': fakePages('/c/4', 3),
      },
    );
    final s = f.make(source: src);
    await s.open();
    await pumpEventQueue();
    expect(loaded(s), ['/c/2', '/c/3']);
    s.onItem(s.strip.itemForPage(1));
    await pumpEventQueue();
    expect(src.asked, isNot(contains('/c/4')), reason: '5 pages still ahead');
    s.onItem(s.strip.itemForPage(2));
    await pumpEventQueue();
    expect(loaded(s), ['/c/2', '/c/3', '/c/4']);
  });
}
