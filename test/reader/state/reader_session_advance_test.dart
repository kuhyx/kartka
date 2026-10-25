import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// Chapter 2 has 5 pages, chapter 3 has 3; [next] overrides chapter 3.
class _Source extends FakeSource {
  new({this.next})
    : super(
        chapterList: sessionChapters,
        pageMap: {
          '/c/1': fakePages('/c/1', 2),
          '/c/2': fakePages('/c/2', 5),
          '/c/3': fakePages('/c/3', 3),
        },
      );

  Future<List<PageRef>> Function()? next;

  @override
  Future<List<PageRef>> pages(String chapterUrl) {
    final override = next;
    if (chapterUrl == '/c/3' && override != null) {
      pageCalls.add(chapterUrl);
      return override();
    }
    return super.pages(chapterUrl);
  }
}

void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());

  Future<ReaderSession> opened(_Source source, {bool atEnd = false}) async {
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 1));
    final s = f.make(source: source, startAtEnd: atEnd);
    await s.open();
    return s;
  }

  Future<void> idle() => Future<void>.delayed(Duration.zero);

  test(
    'nearing the end appends the next chapter with no slot between',
    () async {
      final source = _Source();
      final s = await opened(source);
      expect(source.pageCalls, ['/c/2']);
      s.onItem(4);
      expect(s.nextLoading, isTrue);
      await idle();
      expect(source.pageCalls, ['/c/2', '/c/3']);
      expect(s.strip.pageCounts, [5, 3]);
      expect(s.strip.slotAt(6), const StripSlot.page(0, segment: 1, flat: 5));
      expect(s.chapterName, 'Ch. 2');
      s.onItem(6);
      expect(s.segment, 1);
      expect(s.page, 0);
      expect(s.chapterName, 'Ch. 3');
      expect(s.pages, hasLength(3));
      expect(s.neighbours.next, isNull);
      expect(s.nextChapter, isNull);
      expect(await s.image(5), hasLength(1));
      expect(f.fetched, contains('https://img.test/c/3/0.png'));
    },
  );

  test('progress follows the chapter being read', () {
    fakeAsync((async) {
      final source = _Source();
      final s = f.make(source: source);
      unawaited(s.open());
      async.flushMicrotasks();
      for (var item = 1; item <= 7; item++) {
        s.onItem(item);
        async.flushMicrotasks();
      }
      async.elapse(const Duration(seconds: 1));
      expect(f.progress.markedRead, ['/c/2']);
      final last = f.progress.recorded.last;
      expect(last.chapterUrl, '/c/3');
      expect(last.chapterNumber, 3);
      expect(last.page, 1);
      s.onItem(9);
      async.flushMicrotasks();
      expect(s.page, 2);
      expect(f.progress.markedRead, ['/c/2', '/c/3']);
      s.dispose();
    });
  });

  test(
    'a reader waiting on the trailing slot moves into the next chapter',
    () async {
      final gate = Completer<List<PageRef>>();
      final source = _Source(next: () => gate.future);
      final s = await opened(source);
      s.onItem(6);
      expect(s.segment, 0);
      expect(s.page, 4);
      gate.complete(fakePages('/c/3', 3));
      await idle();
      expect(s.segment, 1);
      expect(s.page, 0);
      expect(s.nextLoading, isFalse);
    },
  );

  test('a failed advance is shown redacted, logged, and retried', () async {
    var fail = true;
    final source = _Source(
      next: () async {
        if (fail) {
          throw StateError('GET https://src.test/c/3?token=SECRET -> 500');
        }
        return fakePages('/c/3', 3);
      },
    );
    final s = await opened(source);
    s.onItem(6);
    await idle();
    expect(s.nextError, contains('https://src.test/c/3?<redacted>'));
    expect(s.nextError, isNot(contains('SECRET')));
    final logged = (await f.diagnostics.entries()).single;
    expect(logged.kind, 'reader.advance');
    expect(logged.sourceId, 'fake');
    expect(logged.mangaUrl, '/m/1');
    expect(logged.chapterUrl, '/c/3');
    expect(logged.at, DateTime.utc(2026, 10, 24));
    expect(logged.toJson().toString(), isNot(contains('SECRET')));
    s.onItem(5);
    await idle();
    expect(source.pageCalls.where((c) => c == '/c/3'), hasLength(1));
    fail = false;
    s.retryNext();
    await idle();
    expect(s.nextError, isNull);
    expect(s.strip.pageCounts, [5, 3]);
  });

  test('a fling past a chapter end still marks that chapter read', () async {
    final s = await opened(_Source());
    s.onItem(4);
    await idle();
    expect(s.strip.pageCounts, [5, 3]);
    s.onItem(7);
    await idle();
    expect(s.segment, 1);
    expect(f.progress.markedRead, ['/c/2']);
    s.dispose();
  });

  test('an empty next chapter is a failure', () async {
    final s = await opened(_Source(next: () async => const []));
    s.onItem(6);
    await idle();
    expect(s.nextError, contains('no pages'));
    expect((await f.diagnostics.entries()).single.error, contains('no pages'));
  });

  test('a next chapter that never answers times out', () {
    fakeAsync((async) {
      final source = _Source(next: () => Completer<List<PageRef>>().future);
      final s = f.make(
        source: source,
        advanceTimeout: const Duration(seconds: 5),
      );
      unawaited(s.open());
      async.flushMicrotasks();
      s.onItem(6);
      async.elapse(const Duration(seconds: 6));
      expect(s.nextError, contains('Timed out'));
      s.dispose();
    });
  });

  test('the last chapter has nothing to load', () async {
    final source = _Source();
    final s = f.make(source: source, chapter: '/c/3');
    await s.open();
    s.onItem(4);
    await idle();
    expect(s.nextChapter, isNull);
    expect(s.nextLoading, isFalse);
    expect(source.pageCalls, ['/c/3']);
  });

  test('a reader left while the next chapter loads drops it', () async {
    final gate = Completer<List<PageRef>>();
    final s = await opened(_Source(next: () => gate.future));
    s
      ..onItem(5)
      ..dispose();
    gate.complete(fakePages('/c/3', 3));
    await idle();
    expect(s.strip.pageCounts, [5]);
  });

  test('opening at the end lands on the last page without reading it', () {
    fakeAsync((async) {
      final s = f.make(source: _Source(), startAtEnd: true);
      unawaited(s.open());
      async.flushMicrotasks();
      expect(s.page, 4);
      expect(s.initialItem, 5);
      s.onItem(5);
      async.elapse(const Duration(seconds: 1));
      expect(f.progress.recorded, isEmpty);
      expect(f.progress.markedRead, isEmpty);
      s.onItem(4);
      async.elapse(const Duration(seconds: 1));
      expect(f.progress.recorded.single.page, 3);
      s.dispose();
    });
  });
}
