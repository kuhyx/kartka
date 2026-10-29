import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// Chapters 1-4, newest first.
const List<ChapterInfo> _four = [
  ChapterInfo(url: '/c/4', name: 'Ch. 4', number: 4),
  ...sessionChapters,
];

/// Chapter 2 has 5 pages, 3 has 3, 4 has 2. The chapter list fails while
/// [listFailures] is above zero, or comes back as [list].
class _Source extends FakeSource {
  new({this.listFailures = 0, this.list = _four})
    : super(
        pageMap: {
          '/c/2': fakePages('/c/2', 5),
          '/c/3': fakePages('/c/3', 3),
          '/c/4': fakePages('/c/4', 2),
        },
      );

  int listFailures;
  List<ChapterInfo> list;
  Completer<List<ChapterInfo>>? gate;
  int listCalls = 0;

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    listCalls++;
    final wait = gate;
    if (wait != null) return await wait.future;
    if (listFailures > 0) {
      listFailures--;
      throw StateError('GET https://src.test/m/1?token=SECRET -> 503');
    }
    return list;
  }
}

void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());

  Future<ReaderSession> opened(_Source source) async {
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 0));
    final s = f.make(source: source);
    await s.open();
    return s;
  }

  Future<void> idle() => Future<void>.delayed(Duration.zero);

  test('the next chapter loads on open, not on the last page', () async {
    final source = _Source();
    final s = await opened(source);
    await idle();
    expect(source.pageCalls, ['/c/2', '/c/3']);
    expect(s.strip.pageCounts, [5, 3]);
    s.onItem(3);
    await idle();
    expect(source.pageCalls, ['/c/2', '/c/3'], reason: 'one chapter ahead');
    s.onItem(6);
    await idle();
    expect(s.segment, 1);
    expect(source.pageCalls, ['/c/2', '/c/3', '/c/4']);
    expect(s.strip.pageCounts, [5, 3, 2]);
  });

  test('a chapter list that failed at open is fetched again', () async {
    final source = _Source(listFailures: 1);
    final s = await opened(source);
    await idle();
    await idle();
    expect(source.listCalls, 2);
    expect(s.neighbours.current?.url, '/c/2');
    expect(s.neighbours.next?.url, '/c/3');
    expect(s.strip.pageCounts, [5, 3]);
    s.onItem(5);
    await idle();
    expect(f.progress.recorded.single.chapterNumber, 2);
    expect(f.progress.markedRead, ['/c/2']);
  });

  test('while the list is fetched again the next chapter is loading', () async {
    final source = _Source(listFailures: 2);
    final s = await opened(source);
    await idle();
    expect(s.nextError, isNotNull);
    final gate = source.gate = Completer();
    s.retryNext();
    expect(s.nextLoading, isTrue);
    expect(s.nextError, isNull);
    gate.complete(_four);
    await idle();
    await idle();
    expect(s.nextLoading, isFalse);
    expect(s.strip.pageCounts, [5, 3]);
  });

  test(
    'a list that keeps failing is a redacted, logged advance error',
    () async {
      final source = _Source(listFailures: 2);
      final s = await opened(source);
      await idle();
      expect(s.nextChapter, isNull);
      expect(s.nextError, contains('https://src.test/m/1?<redacted>'));
      expect(s.nextError, isNot(contains('SECRET')));
      final logged = (await f.diagnostics.entries()).single;
      expect(logged.kind, 'reader.advance');
      expect(logged.toJson().toString(), isNot(contains('SECRET')));
      s.retryNext();
      await idle();
      await idle();
      expect(s.nextError, isNull);
      expect(s.strip.pageCounts, [5, 3]);
    },
  );

  test('a chapter missing from the list is an error, not the end', () async {
    final source = _Source(
      listFailures: 1,
      list: const [ChapterInfo(url: '/c/9', name: 'Ch. 9', number: 9)],
    );
    final s = await opened(source);
    await idle();
    expect(s.nextChapter, isNull);
    expect(s.nextError, contains('chapter list'));
    expect(s.nextLoading, isFalse);
  });

  test('without a source the next chapter cannot be found', () async {
    final s = f.make(
      source: FakeSource(id: 'other'),
      downloads: FakeDownloads({'/c/2': fakePages('/c/2', 2)}),
    );
    await s.open();
    await idle();
    expect(s.nextError, contains('source'));
  });

  test('the known last chapter just ends', () async {
    final source = _Source(list: sessionChapters);
    final s = f.make(source: source, chapter: '/c/3');
    await s.open();
    await idle();
    expect(source.listCalls, 1);
    expect(s.nextChapter, isNull);
    expect(s.nextError, isNull);
    expect(s.nextLoading, isFalse);
  });
}
