import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());
  ReaderSession make({
    FakeSource? source,
    FakeDownloads? downloads,
    ReadingProgress? saved,
  }) => f.make(source: source, downloads: downloads, saved: saved);

  test('opens with neighbours, settings, mode and prefetch', () async {
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 2));
    await f.prefs.setModeFor('fake|/m/1', ReaderMode.webtoon);
    final s = make();
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(s.pages, hasLength(5));
    expect(s.offline, isFalse);
    expect(s.chapterName, 'Ch. 2');
    expect(s.neighbours.previous?.url, '/c/1');
    expect(s.neighbours.next?.url, '/c/3');
    expect(s.mode, ReaderMode.webtoon);
    expect(s.page, 0);
    expect(s.initialItem, 1);
    expect(s.strip.itemCount, 7);
    await Future<void>.delayed(Duration.zero);
    expect(f.fetched, [
      'https://img.test/c/2/0.png',
      'https://img.test/c/2/1.png',
      'https://img.test/c/2/2.png',
    ]);
    expect(await s.image(0), hasLength(1));
  });

  test('resumes the saved page of the same chapter', () async {
    final s = make(
      saved: ReadingProgress(
        key: 'fake|/m/1',
        chapterUrl: '/c/2',
        chapterNumber: 2,
        page: 3,
        readAt: DateTime.utc(2026),
      ),
    );
    await s.open();
    expect(s.page, 3);
    expect(s.initialItem, 4);
  });

  test('a finished or other chapter starts at the first page', () async {
    for (final saved in [('/c/2', 4), ('/c/1', 2)]) {
      final s = make(
        saved: ReadingProgress(
          key: 'fake|/m/1',
          chapterUrl: saved.$1,
          chapterNumber: 2,
          page: saved.$2,
          readAt: DateTime.utc(2026),
        ),
      );
      await s.open();
      expect(s.page, 0);
    }
  });

  test('load failures surface as a failed phase', () async {
    final s = make(source: FakeSource(id: 'other'));
    await s.open();
    expect(s.phase, ReaderPhase.failed);
    expect(s.error, contains('not downloaded'));
    final t = make(source: FakeSource(chapterList: sessionChapters));
    await t.open();
    expect(t.phase, ReaderPhase.failed);
    expect(t.error, contains('no pages'));
  });

  test('an open failure is logged as reader.open with its chapter', () async {
    final s = make(source: FakeSource(chapterList: sessionChapters));
    await s.open();
    final e = (await f.diagnostics.entries()).single;
    expect(e.kind, 'reader.open');
    expect(e.error, contains('no pages'));
    expect((e.sourceId, e.mangaUrl, e.chapterUrl), ('fake', '/m/1', '/c/2'));
  });

  test('a page the reader fails to show is logged as reader.page', () async {
    // Chapter 3 has pages: the next chapter loads on open, and only page
    // failures are under test here.
    FakeSource withNext() => FakeSource(
      chapterList: sessionChapters,
      pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 5)},
    );
    final s = make(source: withNext());
    await s.open();
    await pumpEventQueue();
    expect(await f.diagnostics.entries(), isEmpty, reason: 'prefetch is quiet');
    f.imageError = StateError('HTTP 404');
    s.retry();
    final failed = make(source: withNext());
    await failed.open();
    await expectLater(failed.image(0), throwsStateError);
    await pumpEventQueue();
    final e = (await f.diagnostics.entries()).single;
    expect(e.kind, 'reader.page');
    expect(e.error, 'Bad state: HTTP 404');
    expect(e.sourceId, 'fake');
  });

  test('page changes record debounced progress and mark the end read', () {
    fakeAsync((async) {
      final s = make();
      unawaited(s.open());
      async.flushMicrotasks();
      s
        ..onItem(2)
        ..onItem(3);
      async.elapse(const Duration(seconds: 1));
      expect(f.progress.recorded.single.page, 2);
      expect(f.progress.recorded.single.chapterNumber, 2);
      expect(f.progress.recorded.single.chapterUrl, '/c/2');
      expect(f.progress.recorded.single.pageCount, 5);
      s.onItem(6);
      async.flushMicrotasks();
      expect(s.page, 4);
      expect(f.progress.recorded.last.page, 4);
      expect(f.progress.markedRead, ['/c/2']);
      s
        ..onItem(0)
        ..dispose();
      async.flushMicrotasks();
      expect(s.page, 0);
      expect(f.progress.recorded, hasLength(2));
    });
  });

  test('mode and settings changes persist and notify', () async {
    final s = make();
    await s.open();
    // Let the next chapter's load (started on open) settle first.
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    s.addListener(() => notified++);
    await s.setMode(ReaderMode.pagedLtr);
    expect(await f.prefs.modeFor('fake|/m/1'), ReaderMode.pagedLtr);
    await s.updateSettings(const ReaderSettings(prefetchAhead: 0));
    expect((await f.prefs.settings()).prefetchAhead, 0);
    expect(s.settings.prefetchAhead, 0);
    s.retry();
    expect(notified, 3);
  });

  test('calls before open are harmless', () {
    final s = make();
    expect(s.phase, ReaderPhase.loading);
    s
      ..onItem(1)
      ..dispose();
  });
}
