import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/cover_cache.dart';

Uint8List _png(String tag) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...utf8.encode(tag)]);

/// A page fetch must not queue behind covers on the server's rate limiter
/// (89e1ec6e): while a yield is open, un-started covers wait; in-flight
/// covers finish; the held ones then start, newest first, capped by
/// [CoverCache.maxLoads].
void main() {
  test('a cover requested while held starts on release', () async {
    final started = <String>[];
    final gates = <String, Completer<Uint8List>>{};
    final pending = Completer<Object?>();
    final cache = CoverCache(
      load: (url) {
        started.add(url);
        return (gates[url] = Completer<Uint8List>()).future;
      },
      releaseGrace: Duration.zero,
    )..yieldTo(pending.future);
    await pumpEventQueue();
    final held = cache.get('https://a.test/0.jpg');
    unawaited(held);
    await pumpEventQueue();
    expect(started, isEmpty, reason: 'the page fetch holds covers back');
    pending.complete();
    await pumpEventQueue();
    expect(started, ['https://a.test/0.jpg']);
  });

  test(
    'a cover that started before the hold still completes while held',
    () async {
      final gates = <String, Completer<Uint8List>>{};
      final pending = Completer<Object?>();
      final cache = CoverCache(
        load: (url) => (gates[url] = Completer<Uint8List>()).future,
      );
      final cover = cache.get('https://a.test/0.jpg');
      await pumpEventQueue();
      expect(
        gates['https://a.test/0.jpg'],
        isNotNull,
        reason: 'the load started before the hold',
      );
      cache.yieldTo(pending.future);
      gates['https://a.test/0.jpg']!.complete(_png('0'));
      expect(await cover, _png('0'));
      pending.complete();
      await pumpEventQueue();
    },
  );

  test('a failed release also starts held covers', () async {
    final started = <String>[];
    final gates = <String, Completer<Uint8List>>{};
    final pending = Completer<Object?>();
    pending.future.ignore();
    final cache = CoverCache(
      load: (url) {
        started.add(url);
        return (gates[url] = Completer<Uint8List>()).future;
      },
      releaseGrace: Duration.zero,
    )..yieldTo(pending.future);
    await pumpEventQueue();
    final held = cache.get('https://a.test/0.jpg');
    unawaited(held);
    await pumpEventQueue();
    expect(started, isEmpty);
    pending.completeError(StateError('x'));
    await pumpEventQueue();
    expect(started, ['https://a.test/0.jpg']);
  });

  test('a release that never happens expires after maxHold', () {
    fakeAsync((async) {
      final started = <String>[];
      final cache = CoverCache(
        load: (url) {
          started.add(url);
          return Completer<Uint8List>().future;
        },
        maxHold: const Duration(milliseconds: 20),
        releaseGrace: Duration.zero,
      )..yieldTo(Completer<Object?>().future);
      unawaited(cache.get('https://a.test/0.jpg'));
      async.elapse(const Duration(milliseconds: 19));
      expect(started, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(started, ['https://a.test/0.jpg']);
    });
  });

  test('covers are held until every release is over', () async {
    final started = <String>[];
    final gates = <String, Completer<Uint8List>>{};
    final pending1 = Completer<Object?>();
    final pending2 = Completer<Object?>();
    final cache =
        CoverCache(
            load: (url) {
              started.add(url);
              return (gates[url] = Completer<Uint8List>()).future;
            },
            releaseGrace: Duration.zero,
          )
          ..yieldTo(pending1.future)
          ..yieldTo(pending2.future);
    await pumpEventQueue();
    final held = cache.get('https://a.test/0.jpg');
    unawaited(held);
    await pumpEventQueue();
    expect(started, isEmpty);
    pending1.complete();
    await pumpEventQueue();
    expect(started, isEmpty, reason: 'the second hold is still open');
    pending2.complete();
    await pumpEventQueue();
    expect(started, ['https://a.test/0.jpg']);
  });

  test('after release exactly maxLoads start, newest first; a finish starts '
      'the next', () async {
    final started = <String>[];
    final gates = <String, Completer<Uint8List>>{};
    final pending = Completer<Object?>();
    // maxLoads defaults to 2.
    final cache = CoverCache(
      load: (url) {
        started.add(url);
        return (gates[url] = Completer<Uint8List>()).future;
      },
      releaseGrace: Duration.zero,
    )..yieldTo(pending.future);
    await pumpEventQueue();
    final held = [
      for (var i = 0; i < 4; i++) cache.get('https://a.test/$i.jpg'),
    ];
    unawaited(Future.wait(held));
    await pumpEventQueue();
    pending.complete();
    await pumpEventQueue();
    expect(started, [
      'https://a.test/3.jpg',
      'https://a.test/2.jpg',
    ], reason: 'exactly maxLoads start, newest first');
    gates['https://a.test/3.jpg']!.complete(_png('3'));
    await pumpEventQueue();
    expect(
      started.last,
      'https://a.test/1.jpg',
      reason: 'a finish starts the next newest',
    );
  });

  // Measured 2026-11-27: covers released between two back-to-back page
  // fetches (30-60 ms apart) put the next fetch at 1.7 s; with no covers
  // it took 0.7 s at most.
  test('a page fetch right after another keeps covers held', () {
    fakeAsync((async) {
      final started = <String>[];
      final cache = CoverCache(
        load: (url) {
          started.add(url);
          return Completer<Uint8List>().future;
        },
      );
      final first = Completer<Object?>();
      cache.yieldTo(first.future);
      unawaited(cache.get('https://a.test/0.jpg'));
      async.flushMicrotasks();
      first.complete();
      async.elapse(const Duration(milliseconds: 60));
      expect(started, isEmpty, reason: 'the next page is about to start');
      final second = Completer<Object?>();
      cache.yieldTo(second.future);
      async.elapse(const Duration(seconds: 1));
      expect(started, isEmpty, reason: 'the next page is running');
      second.complete();
      async.elapse(cache.releaseGrace);
      expect(started, ['https://a.test/0.jpg']);
      async.flushTimers();
    });
  });

  test('a cover asked for during the grace waits for its end', () {
    fakeAsync((async) {
      final started = <String>[];
      final cache = CoverCache(
        load: (url) {
          started.add(url);
          return Completer<Uint8List>().future;
        },
      );
      final page = Completer<Object?>();
      cache.yieldTo(page.future);
      async.flushMicrotasks();
      page.complete();
      async.elapse(const Duration(milliseconds: 10));
      unawaited(cache.get('https://a.test/0.jpg'));
      async.flushMicrotasks();
      expect(started, isEmpty);
      async.elapse(cache.releaseGrace);
      expect(started, ['https://a.test/0.jpg']);
    });
  });
}
