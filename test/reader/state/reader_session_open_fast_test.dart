import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// A source that logs when the reader asks for its chapter list.
class _LoggedList extends FakeSource {
  new(this.log, {super.pageMap}) : super(chapterList: sessionChapters);

  final List<String> log;

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) {
    log.add('list');
    return super.chapters(mangaUrl);
  }
}

/// A source whose chapter list waits on [gate] (Suwayomi fetching it from
/// the site).
class _SlowList extends FakeSource {
  new({required this.gate, super.pageMap})
    : super(chapterList: sessionChapters);

  final Completer<void> gate;

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    await gate.future;
    return await super.chapters(mangaUrl);
  }
}

/// reader.open waited on the source lookup and the chapter list before the
/// pages (971debc8, 1.7-2.3 s). Neither holds the open now: the list fills
/// in the neighbours when it arrives.
void main() {
  late FakeProgress progress;

  ReaderSession make(
    FakeSource src, {
    Future<void>? sourceReady,
    FakeDownloads? downloads,
    Future<Uint8List> Function(PageRef)? loadImage,
  }) {
    progress = FakeProgress();
    return ReaderSession(
      sourceId: src.id,
      mangaUrl: '/m/1',
      chapterUrl: '/c/2',
      deps: ReaderDeps(
        findSource: (id) async {
          await sourceReady;
          return src;
        },
        progress: progress,
        downloads: downloads,
        prefs: ReaderPrefs(MemoryKeyValueStore()),
        loadImage: loadImage ?? (_) async => Uint8List(1),
        now: () => DateTime.utc(2026, 10, 24),
      ),
    );
  }

  test('a downloaded chapter opens before the source is found', () async {
    final found = Completer<void>();
    final gate = Completer<void>();
    final s = make(
      _SlowList(gate: gate),
      sourceReady: found.future,
      downloads: FakeDownloads({'/c/2': fakePages('/c/2', 3)}),
    );
    // Gates still shut: an open that waits on them times out here.
    await s.open().timeout(const Duration(seconds: 1));
    expect(s.phase, ReaderPhase.ready);
    expect(s.offline, isTrue);
    expect(s.nextLoading, isTrue, reason: 'the next chapter is unknown yet');
    found.complete();
    gate.complete();
    await pumpEventQueue();
    expect(s.neighbours.current?.name, 'Ch. 2');
    expect(s.nextChapter?.url, '/c/3');
  });

  test('an online chapter opens before its chapter list arrives, and the '
      'a page turned meanwhile is recorded once the list numbers it', () async {
    final gate = Completer<void>();
    final s = make(
      _SlowList(gate: gate, pageMap: {'/c/2': fakePages('/c/2', 3)}),
    );
    await s.open().timeout(const Duration(seconds: 1));
    expect(s.phase, ReaderPhase.ready);
    expect(s.offline, isFalse);
    s.onItem(2); // Page 1 (item 0 is the previous chapter's slot).
    // Past the recorder's debounce, still without the list.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    gate.complete();
    await pumpEventQueue();
    expect(s.nextChapter?.url, '/c/3');
    expect(progress.recorded.map((p) => (p.chapterNumber, p.page)), [(2, 1)]);
  });

  test('a list arriving after the reader closed changes nothing', () async {
    final gate = Completer<void>();
    final s = make(
      _SlowList(gate: gate, pageMap: {'/c/2': fakePages('/c/2', 3)}),
    );
    await s.open().timeout(const Duration(seconds: 1));
    s.dispose();
    gate.complete();
    await pumpEventQueue();
    expect(s.neighbours.current, isNull);
  });

  // A chapter list refresh beside the open slowed Suwayomi's page list from
  // 0.12 s to 2.1 s and page 1 from 0.4 s to 1.3 s (one rate-limited
  // source): the list waits until page 1 has arrived or failed.
  for (final fails in [false, true]) {
    test('an online open asks for the chapter list only once page 1 has '
        '${fails ? 'failed' : 'arrived'}', () async {
      final log = <String>[];
      final first = Completer<Uint8List>();
      final s = make(
        _LoggedList(log, pageMap: {'/c/2': fakePages('/c/2', 3)}),
        loadImage: (p) {
          log.add('image ${p.index}');
          return p.index == 0 ? first.future : Future.value(Uint8List(1));
        },
      );
      await s.open().timeout(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(log, ['image 0'], reason: 'page 1 goes alone');
      if (fails) {
        first.completeError(StateError('500'));
      } else {
        first.complete(Uint8List(1));
      }
      await pumpEventQueue();
      expect(log, contains('list'));
      expect(s.nextChapter?.url, '/c/3');
    });
  }

  test('a chapter with no pages asks for the list at once', () async {
    final log = <String>[];
    final s = make(_LoggedList(log, pageMap: {'/c/2': const []}));
    await s.open().timeout(const Duration(seconds: 1));
    await pumpEventQueue();
    expect(log, ['list']);
    expect(s.nextChapter?.url, '/c/3');
  });
}
