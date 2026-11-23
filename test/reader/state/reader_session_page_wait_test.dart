import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/shown_page_wait.dart';

import '../support/fakes.dart';

import 'session_fixture.dart';

/// The page-wait probe (28fffd0a): a shown page that spun 1 s or more is
/// logged as `reader.pagewait`, naming the step and the image host.
void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());

  Future<List<String>> probes() async => [
    for (final e in await f.diagnostics.entries())
      if (e.kind == 'reader.pagewait') e.error,
  ];

  test('a shown page held 1.5 s names its fetch and host', () async {
    final gate = f.imageGates['https://img.test/c/2/0.png'] = Completer();
    final s = f.make();
    await s.open();
    s.image(0).ignore();
    f.clock = f.clock.add(const Duration(milliseconds: 1500));
    gate.complete();
    await pumpEventQueue();
    expect(await probes(), [
      contains('ReaderProbe: fake page waited on open from img.test'),
    ]);
  });

  test('a page already in is not timed; a quick one is not logged', () async {
    final s = f.make();
    await s.open();
    await s.image(0);
    f.clock = f.clock.add(const Duration(seconds: 3));
    await s.image(0);
    s.image(1).ignore();
    await pumpEventQueue();
    expect(await probes(), isEmpty);
  });

  test('an off-screen neighbour that spins is not timed', () async {
    final gate = f.imageGates['https://img.test/c/2/2.png'] = Completer();
    final s = f.make();
    await s.open();
    s.image(2).ignore();
    f.clock = f.clock.add(const Duration(seconds: 3));
    gate.complete();
    await pumpEventQueue();
    expect(await probes(), isEmpty);
  });

  Future<void> wait2s(Completer<void> gate) async {
    f.clock = f.clock.add(const Duration(seconds: 2));
    gate.complete();
    await pumpEventQueue();
  }

  test('a turn past the look-aheads names turn', () async {
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 1));
    final gate = f.imageGates['https://img.test/c/2/4.png'] = Completer();
    final s = f.make();
    await s.open();
    await s.image(0);
    s
      ..onItem(s.strip.itemForPage(4))
      ..image(4).ignore();
    await wait2s(gate);
    expect(await probes(), [contains('waited on turn from img.test')]);
  });

  test('the first page past a chapter edge names advance', () async {
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 0));
    final gate = f.imageGates['https://img.test/c/3/0.png'] = Completer();
    final s = f.make(source: _threeChapters());
    await s.open();
    await s.image(0);
    s.onItem(s.strip.itemForPage(4));
    await pumpEventQueue();
    expect(s.segments, hasLength(2));
    s
      ..onItem(s.strip.itemForPage(0, segment: 1))
      ..image(5).ignore();
    await wait2s(gate);
    expect(await probes(), [contains('waited on advance from img.test')]);
  });

  test('joining a page the details screen warmed names warm', () async {
    final gate = f.imageGates['https://img.test/c/2/0.png'] = Completer();
    final began = f.clock.subtract(const Duration(milliseconds: 50));
    final s = f.make(imageStarted: (_) => (at: began, warm: true));
    await s.open();
    s.image(0).ignore();
    await wait2s(gate);
    expect(await probes(), [contains('waited on warm from img.test')]);
  });

  test('the shown page holds the gate until it arrives', () async {
    final gate = f.imageGates['https://img.test/c/2/0.png'] = Completer();
    final shown = ShownPageWait();
    final s = f.make(shownPages: shown);
    await s.open();
    s.image(0).ignore();
    expect(shown.busy, isTrue);
    gate.complete();
    await pumpEventQueue();
    expect(shown.busy, isFalse);
  });

  test('leaving the reader releases its shown page', () async {
    f.imageGates['https://img.test/c/2/0.png'] = Completer();
    final shown = ShownPageWait();
    final s = f.make(shownPages: shown);
    await s.open();
    expect(shown.busy, isTrue);
    s.dispose();
    expect(shown.busy, isFalse);
  });

  test('the next chapter waits for the shown page, at most maxHold', () {
    fakeAsync((async) {
      f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 0)).ignore();
      final gate = f.imageGates['https://img.test/c/2/2.png'] = Completer();
      final source = _LateList();
      final s = f.make(source: source, shownPages: ShownPageWait());
      s.open().ignore();
      async.flushMicrotasks();
      s
        ..onItem(s.strip.itemForPage(2))
        ..image(2).ignore();
      source.list.complete(sessionChapters);
      async.flushMicrotasks();
      expect(source.pageCalls, ['/c/2']);
      gate.complete();
      async.flushMicrotasks();
      expect(source.pageCalls, ['/c/2', '/c/3']);
    });
  });

  test('a stuck shown page holds the next chapter 3 s at most', () {
    fakeAsync((async) {
      f.imageGates['https://img.test/c/2/2.png'] = Completer();
      final source = _LateList();
      final s = f.make(source: source, shownPages: ShownPageWait());
      s.open().ignore();
      async.flushMicrotasks();
      s.onItem(s.strip.itemForPage(2));
      source.list.complete(sessionChapters);
      async.elapse(const Duration(milliseconds: 2900));
      expect(source.pageCalls, ['/c/2']);
      async.elapse(const Duration(milliseconds: 100));
      expect(source.pageCalls, ['/c/2', '/c/3']);
    });
  });
}

/// A source whose chapter list arrives when [list] completes.
class _LateList extends FakeSource {
  new()
    : super(
        chapterList: sessionChapters,
        pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
      );

  final list = Completer<List<ChapterInfo>>();

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) => list.future;
}

FakeSource _threeChapters() => FakeSource(
  chapterList: sessionChapters,
  pageMap: {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)},
);
