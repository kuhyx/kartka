import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/data/page_image_warmer.dart';

PageRef _p(int i) => PageRef(index: i, imageUrl: 'https://s.test/p$i.jpg');

/// The first pages of the Continue chapter are fetched ahead, so the
/// reader's first pages draw at once: a MangaFire page costs 0.5-0.9 s on
/// the server, and the first one was a reported reader.page wait (28fffd0a).
void main() {
  late List<String> asked;
  late Map<String, Completer<Uint8List>> pending;
  late PageImageWarmer warmer;

  setUp(() {
    asked = [];
    pending = {};
    warmer = PageImageWarmer((page) {
      asked.add(page.imageUrl);
      return (pending[page.imageUrl] = Completer<Uint8List>()).future;
    }, capacity: 4);
  });

  test('warms [count] pages from a start, one at a time, and the reader '
      'gets them without a second fetch', () async {
    final pages = [for (var i = 0; i < 6; i++) _p(i)];
    final done = warmer.warm(pages, from: 1);
    await pumpEventQueue();
    expect(asked, [pages[1].imageUrl], reason: 'serial: rate-limited');
    pending[pages[1].imageUrl]!.complete(Uint8List(1));
    await pumpEventQueue();
    pending[pages[2].imageUrl]!.complete(Uint8List(2));
    await pumpEventQueue();
    pending[pages[3].imageUrl]!.complete(Uint8List(3));
    await done;
    expect(asked, [
      for (final i in [1, 2, 3]) pages[i].imageUrl,
    ]);
    expect(await warmer.load(pages[2]), hasLength(2));
    expect(asked, hasLength(3));
    unawaited(warmer.load(pages[5]));
    expect(asked.last, pages[5].imageUrl, reason: 'not warmed: fetched');
  });

  test('a page still warming is joined, not fetched twice', () async {
    unawaited(warmer.warm([_p(0)]));
    await pumpEventQueue();
    final shown = warmer.load(_p(0));
    pending[_p(0).imageUrl]!.complete(Uint8List(7));
    expect(await shown, hasLength(7));
    expect(asked, hasLength(1));
  });

  test('a failed warm-up is dropped, so the reader fetches again', () async {
    final done = warmer.warm([_p(0), _p(1)]);
    await pumpEventQueue();
    pending[_p(0).imageUrl]!.completeError(StateError('500'));
    await pumpEventQueue();
    pending[_p(1).imageUrl]!.complete(Uint8List(1));
    await done;
    unawaited(warmer.load(_p(0)).then((_) {}, onError: (Object _) {}));
    expect(asked, [_p(0).imageUrl, _p(1).imageUrl, _p(0).imageUrl]);
  });

  test('only [capacity] pages are kept, the oldest dropped', () async {
    final pages = [for (var i = 0; i < 6; i++) _p(i)];
    for (final p in pages) {
      final done = warmer.warm([p]);
      await pumpEventQueue();
      pending[p.imageUrl]!.complete(Uint8List(1));
      await done;
    }
    unawaited(warmer.load(pages[0]));
    unawaited(warmer.load(pages[5]));
    expect(asked, [...pages.map((p) => p.imageUrl), pages[0].imageUrl]);
  });

  test(
    'two chapters warming at once fetch one page at a time in total',
    () async {
      final done1 = warmer.warm([_p(0), _p(1)]);
      final done2 = warmer.warm([_p(10), _p(11)]);
      await pumpEventQueue();
      expect(asked.length, 1, reason: 'only one warm fetch at a time');
      pending[_p(0).imageUrl]!.complete(Uint8List(0));
      await pumpEventQueue();
      expect(asked.length, 2);
      pending[_p(1).imageUrl]!.complete(Uint8List(1));
      await pumpEventQueue();
      expect(asked.length, 3);
      pending[_p(10).imageUrl]!.complete(Uint8List(10));
      await pumpEventQueue();
      expect(asked.length, 4);
      pending[_p(11).imageUrl]!.complete(Uint8List(11));
      await Future.wait([done1, done2]);
      expect(asked, [
        _p(0).imageUrl,
        _p(1).imageUrl,
        _p(10).imageUrl,
        _p(11).imageUrl,
      ]);
    },
  );

  test('a warm waits while the reader fetches a page itself', () async {
    final shown = warmer.load(_p(5));
    unawaited(warmer.warm([_p(0)]));
    await pumpEventQueue();
    expect(asked, [
      _p(5).imageUrl,
    ], reason: 'warm did not start while reader fetches');
    pending[_p(5).imageUrl]!.complete(Uint8List(5));
    await shown;
    await pumpEventQueue();
    expect(
      asked.last,
      _p(0).imageUrl,
      reason: 'warm starts after reader finishes',
    );
  });

  test('a failed reader fetch still lets the warm go on', () async {
    final shown = warmer.load(_p(5));
    unawaited(warmer.warm([_p(0)]));
    await pumpEventQueue();
    expect(asked, [_p(5).imageUrl]);
    pending[_p(5).imageUrl]!.completeError(StateError('500'));
    await expectLater(shown, throwsStateError);
    await pumpEventQueue();
    expect(
      asked.last,
      _p(0).imageUrl,
      reason: 'warm continues after reader error',
    );
  });
}
