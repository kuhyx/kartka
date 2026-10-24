import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';
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

  test('without a progress repository it still reads', () async {
    final s = ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: '/c/2',
      deps: ReaderDeps(
        findSource: (_) async =>
            FakeSource(pageMap: {'/c/2': fakePages('/c/2', 2)}),
        prefs: f.prefs,
        loadImage: (p) async => Uint8List(1),
      ),
    );
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    s.onItem(2);
    await Future<void>.delayed(Duration.zero);
    s.dispose();
  });

  test('leaving while the chapter loads starts no fetches', () async {
    final gate = Completer<MangaSource?>();
    final s = ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: '/c/2',
      deps: ReaderDeps(
        findSource: (_) => gate.future,
        prefs: f.prefs,
        loadImage: (p) async {
          f.fetched.add(p.imageUrl);
          return Uint8List(1);
        },
      ),
    );
    final opening = s.open();
    await Future<void>.delayed(Duration.zero);
    s.dispose();
    gate.complete(FakeSource(pageMap: {'/c/2': fakePages('/c/2', 2)}));
    await opening;
    expect(f.fetched, isEmpty);
    expect(s.phase, ReaderPhase.loading);
    s
      ..onItem(1)
      ..retry();
    await s.setMode(ReaderMode.webtoon);
  });

  test(
    'offline with no chapter list: no progress record, still marks read',
    () async {
      final s = make(
        source: FakeSource(id: 'other'),
        downloads: FakeDownloads({'/c/2': fakePages('/c/2', 2)}),
      );
      await s.open();
      s
        ..onItem(1)
        ..onItem(2);
      await Future<void>.delayed(Duration.zero);
      s.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(f.progress.recorded, isEmpty);
      expect(f.progress.markedRead, ['/c/2']);
    },
  );

  test(
    'offline, downloaded chapters supply neighbours and the number',
    () async {
      final s = make(
        source: FakeSource(id: 'other'),
        downloads: FakeDownloads({
          '/c/2': fakePages('/c/2', 2),
        }, sessionChapters),
      );
      await s.open();
      expect(s.chapterName, 'Ch. 2');
      expect(s.neighbours.next?.url, '/c/3');
      s.onItem(2);
      await Future<void>.delayed(Duration.zero);
      expect(f.progress.recorded.single.chapterNumber, 2);
      s.dispose();
    },
  );

  test('a failing downloads lookup still opens the chapter', () async {
    final s = make(
      source: FakeSource(
        failChapters: true,
        pageMap: {'/c/2': fakePages('/c/2', 2)},
      ),
      downloads: _ThrowingChapters(),
    );
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(s.neighbours.current, isNull);
  });
}

class _ThrowingChapters extends FakeDownloads {
  @override
  Future<List<ChapterInfo>> downloadedChapters(MangaKey key) =>
      Future.error(StateError('db'));
}
