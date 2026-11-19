import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/page_cache.dart';

/// The server rate-limits a source: four pages at once took up to 1.95 s
/// each, one at a time 0.15 s (28fffd0a). The shown page goes alone.
void main() {
  late List<int> started;
  late Map<int, Completer<Uint8List>> pending;
  late PageCache cache;

  setUp(() {
    started = [];
    pending = {};
    cache = PageCache(
      fetch: (i) {
        started.add(i);
        return (pending[i] = Completer<Uint8List>()).future;
      },
    );
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  void land(int i) => pending[i]!.complete(Uint8List.fromList([i]));

  test(
    'the current page is fetched alone; look-aheads follow one by one',
    () async {
      cache.focus(5, [6, 7, 8]);
      await settle();
      expect(started, [5]);
      land(5);
      await settle();
      expect(started, [5, 6]);
      land(6);
      await settle();
      expect(started, [5, 6, 7]);
      land(7);
      await settle();
      land(8);
      await settle();
      expect(started, [5, 6, 7, 8]);
    },
  );

  test('a failed current page still releases the look-aheads', () async {
    cache.focus(0, [1]);
    pending[0]!.completeError(StateError('boom'));
    await settle();
    expect(started, [0, 1]);
    expect(cache.contains(0), isFalse);
  });

  test('a page already loaded or in flight releases them at once', () async {
    cache.get(3).ignore();
    land(3);
    await settle();
    cache.focus(3, [4]);
    await settle();
    expect(started, [3, 4]);
  });

  test('a jump goes first and drops the stale look-aheads', () async {
    cache.focus(0, [1, 2, 3]);
    await settle();
    cache.focus(20, [21]);
    await settle();
    expect(started, [0, 20]);
    land(0);
    await settle();
    expect(started, [0, 20], reason: 'old look-aheads never start');
    land(20);
    await settle();
    expect(started, [0, 20, 21]);
  });

  test(
    'a page the UI asks for starts at once, even behind the queue',
    () async {
      cache.focus(0, [1, 2]);
      cache.get(2).ignore();
      await settle();
      expect(started, [0, 2]);
      land(0);
      await settle();
      expect(started, [0, 2, 1]);
      land(1);
      await settle();
      expect(started, [0, 2, 1], reason: '2 is in flight already');
    },
  );

  test('clear stops the queue', () async {
    cache
      ..focus(0, [1])
      ..clear();
    land(0);
    await settle();
    expect(started, [0]);
  });

  test(
    'waitFor starts nothing beside the queue, then takes its turn',
    () async {
      cache.focus(0, [1]);
      final off = cache.waitFor(5);
      final queued = cache.waitFor(1);
      await settle();
      expect(started, [0]);
      land(0);
      await settle();
      expect(started, [0, 1]);
      land(1);
      expect(await queued, [1]);
      await settle();
      expect(started, [0, 1, 5]);
      land(5);
      expect(await off, [5]);
      expect(identical(cache.waitFor(5), cache.get(5)), isTrue);
    },
  );

  test('waitFor on an idle cache fetches the page', () async {
    final page = cache.waitFor(2);
    await settle();
    expect(started, [2]);
    pending[2]!.completeError(StateError('boom'));
    await expectLater(page, throwsStateError);
    cache.waitFor(2).ignore();
    await settle();
    expect(started, [2, 2], reason: 'a failure retries on the next ask');
  });

  test('clear drops pages still waiting for their turn', () async {
    cache.focus(0, const []);
    cache.waitFor(3).ignore();
    cache.clear();
    land(0);
    await settle();
    expect(started, [0]);
  });
}
