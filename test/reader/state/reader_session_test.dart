import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';

const _chapters = [
  ChapterInfo(url: '/c/3', name: 'Ch. 3', number: 3),
  ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2),
  ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
];

void main() {
  late FakeProgress progress;
  late List<String> fetched;
  late ReaderPrefs prefs;

  ReaderSession make({
    FakeSource? source,
    FakeDownloads? downloads,
    ReadingProgress? saved,
    String chapter = '/c/2',
  }) {
    progress = FakeProgress(initial: saved);
    final src =
        source ??
        FakeSource(
          chapterList: _chapters,
          pageMap: {'/c/2': fakePages('/c/2', 5)},
        );
    return ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: chapter,
      deps: ReaderDeps(
        findSource: (id) async => id == src.id ? src : null,
        progress: progress,
        downloads: downloads,
        prefs: prefs,
        loadImage: (p) async {
          fetched.add(p.imageUrl);
          return Uint8List(1);
        },
        now: () => DateTime.utc(2026, 10, 24),
      ),
    );
  }

  setUp(() {
    fetched = [];
    prefs = ReaderPrefs(MemoryKeyValueStore());
  });

  test('opens with neighbours, settings, mode and prefetch', () async {
    await prefs.saveSettings(const ReaderSettings(prefetchAhead: 2));
    await prefs.setModeFor('fake|/m/1', ReaderMode.webtoon);
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
    expect(fetched, [
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

  test('offline pages load without a source or chapter list', () async {
    final s = make(
      source: FakeSource(id: 'other'),
      downloads: FakeDownloads({'/c/2': fakePages('/c/2', 2)}),
    );
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(s.offline, isTrue);
    expect(s.chapterName, 'Chapter');
    expect(s.neighbours.next, isNull);
  });

  test('a failing chapter list still opens the chapter', () async {
    final s = make(
      source: FakeSource(
        failChapters: true,
        pageMap: {'/c/2': fakePages('/c/2', 2)},
      ),
    );
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(s.neighbours.current, isNull);
  });

  test('load failures surface as a failed phase', () async {
    final s = make(source: FakeSource(id: 'other'));
    await s.open();
    expect(s.phase, ReaderPhase.failed);
    expect(s.error, contains('not downloaded'));
    final t = make(source: FakeSource(chapterList: _chapters));
    await t.open();
    expect(t.phase, ReaderPhase.failed);
    expect(t.error, contains('no pages'));
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
      expect(progress.recorded.single.page, 2);
      expect(progress.recorded.single.chapterNumber, 2);
      expect(progress.recorded.single.chapterUrl, '/c/2');
      s.onItem(6);
      async.flushMicrotasks();
      expect(s.page, 4);
      expect(progress.recorded.last.page, 4);
      expect(progress.markedRead, ['/c/2']);
      s
        ..onItem(0)
        ..dispose();
      async.flushMicrotasks();
      expect(s.page, 0);
      expect(progress.recorded, hasLength(2));
    });
  });

  test('mode and settings changes persist and notify', () async {
    final s = make();
    await s.open();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setMode(ReaderMode.pagedLtr);
    expect(await prefs.modeFor('fake|/m/1'), ReaderMode.pagedLtr);
    await s.updateSettings(const ReaderSettings(prefetchAhead: 0));
    expect((await prefs.settings()).prefetchAhead, 0);
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

  test('without a progress repository it still reads', () async {
    final s = ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: '/c/2',
      deps: ReaderDeps(
        findSource: (_) async =>
            FakeSource(pageMap: {'/c/2': fakePages('/c/2', 2)}),
        prefs: prefs,
        loadImage: (p) async => Uint8List(1),
      ),
    );
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    s.onItem(2);
    await Future<void>.delayed(Duration.zero);
    s.dispose();
  });
}
