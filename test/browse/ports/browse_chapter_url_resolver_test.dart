import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/ports/browse_chapter_url_resolver.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// Chapters that wait for [gate], counting fetches in flight.
class _Slow implements MangaSource {
  final gate = Completer<void>();
  int inFlight = 0;
  int peak = 0;
  int calls = 0;

  @override
  SourceRef get ref => const SourceRef(
    id: 's',
    name: 's',
    lang: 'en',
    origin: SourceOrigin.suwayomi,
  );

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    calls++;
    inFlight++;
    if (inFlight > peak) peak = inFlight;
    await gate.future;
    inFlight--;
    return [ChapterInfo(url: '$mangaUrl/1', name: '1', number: 1)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a cold start of many lookups (tracking follows every binding) '
    'fetches at most 2 chapter lists at once; cached ones never wait',
    () async {
      final src = _Slow();
      final store = ChapterStore((id) => id == 's' ? src : null);
      final resolver = BrowseChapterUrlResolver(store);
      final keys = [for (var i = 0; i < 10; i++) mangaKeyOf('s', '/m$i')];
      final all = Future.wait([
        for (final k in keys) resolver.numberOf(k, '${splitMangaKey(k).$2}/1'),
      ]);
      await pumpEventQueue();
      expect(src.peak, 2);
      src.gate.complete();
      expect(await all, everyElement(1));
      expect(src.calls, 10);
      // Cached now: no fetch, no queue.
      expect(await resolver.resolve(keys.first, 1), '/m0/1');
      expect(src.calls, 10);
    },
  );
}
