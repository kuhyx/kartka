import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/reader_settings.dart';

import '../support/fakes.dart';
import 'ahead_fixture.dart';
import 'session_fixture.dart';

/// The trailing slot is "on screen" only while the view reports it as the
/// current item: a neighbour laid out off screen (the paged view builds
/// one each side) is not a wait the reader sees (perf.slow 19643be5).
void main() {
  test('onTrailing follows the reported item', () async {
    final f = SessionFixture();
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 1));
    final source = FakeSource(
      chapterList: sessionChapters,
      pageMap: {'/c/1': fakePages('/c/1', 2), '/c/2': fakePages('/c/2', 5)},
    );
    final s = f.make(source: source);
    await s.open();
    expect(s.onTrailing, isFalse);
    s.onItem(5);
    expect(s.onTrailing, isFalse, reason: 'last page, slot off screen');
    s.onItem(6);
    expect(s.onTrailing, isTrue);
    s.onItem(5);
    expect(s.onTrailing, isFalse);
  });

  group('a wait on the next chapter', () {
    late SessionFixture f;
    setUp(() => f = SessionFixture());

    Future<List<String>> probes() async => [
      for (final e in await f.diagnostics.entries())
        if (e.kind == 'reader.advance' && e.error.contains('ReaderProbe'))
          e.error,
    ];

    Future<void> wait(
      GatedSource src,
      Duration held,
      Completer<void> gate,
    ) async {
      final s = f.make(source: src);
      await s.open();
      await pumpEventQueue();
      s.onItem(6);
      f.clock = f.clock.add(held);
      gate.complete();
      await pumpEventQueue();
      expect(s.segment, 1);
    }

    final pages = {'/c/2': fakePages('/c/2', 5), '/c/3': fakePages('/c/3', 3)};

    test('over 1 s names the page list it waited on', () async {
      final src = GatedSource(pageMap: pages);
      final gate = src.pageGates['/c/3'] = Completer();
      await wait(src, const Duration(milliseconds: 1200), gate);
      expect(await probes(), [contains('next chapter waited on pages')]);
    });

    test('over 1 s names the chapter list it waited on', () async {
      final list = Completer<List<ChapterInfo>>();
      final src = GatedSource(pageMap: pages, list: list);
      final gate = Completer<void>();
      unawaited(gate.future.then((_) => list.complete(sessionChapters)));
      await wait(src, const Duration(seconds: 2), gate);
      expect(await probes(), [contains('next chapter waited on list')]);
    });

    test('over 1 s after an early failure names the retry', () async {
      final map = {'/c/2': fakePages('/c/2', 5)};
      final src = GatedSource(pageMap: map);
      final s = f.make(source: src);
      await s.open();
      await pumpEventQueue();
      s.onItem(6);
      await pumpEventQueue();
      expect(s.nextError, isNotNull, reason: 'failed again on arrival');
      map['/c/3'] = fakePages('/c/3', 3);
      final gate = src.pageGates['/c/3'] = Completer();
      s.retryNext();
      f.clock = f.clock.add(const Duration(seconds: 1));
      gate.complete();
      await pumpEventQueue();
      expect(s.segment, 1);
      expect(await probes(), [contains('next chapter waited on retry')]);
    });

    test('under 1 s is not reported', () async {
      final src = GatedSource(pageMap: pages);
      final gate = src.pageGates['/c/3'] = Completer();
      await wait(src, const Duration(milliseconds: 900), gate);
      expect(await probes(), isEmpty);
    });
  });
}
