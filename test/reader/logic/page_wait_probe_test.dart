import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/page_wait_probe.dart';

void main() {
  late DateTime clock;
  late List<String> slow;
  late PageWaitProbe probe;

  setUp(() {
    clock = DateTime.utc(2026, 11, 23);
    slow = [];
    probe = PageWaitProbe(
      now: () => clock,
      onSlow: (index, step, waited) =>
          slow.add('$index $step ${waited.inMilliseconds}'),
    );
  });

  Future<void> settle(Completer<int> c, Duration after) async {
    clock = clock.add(after);
    c.complete(1);
    await pumpEventQueue();
  }

  test('a wait under 1 s is not reported', () async {
    final c = Completer<int>();
    probe
      ..started(0)
      ..asked(0, c.future);
    await settle(c, const Duration(milliseconds: 999));
    expect(slow, isEmpty);
  });

  test('a fetch started at the turn names fetch after turn', () async {
    final c = Completer<int>();
    probe.started(3);
    clock = clock.add(const Duration(milliseconds: 249));
    probe.asked(3, c.future);
    await settle(c, const Duration(milliseconds: 1500));
    expect(slow, ['3 fetch after turn 1500']);
  });

  test('a page prefetched well before the turn names prefetch', () async {
    final c = Completer<int>();
    probe.started(7);
    clock = clock.add(const Duration(milliseconds: 250));
    probe.asked(7, c.future);
    await settle(c, const Duration(seconds: 2));
    expect(slow, ['7 prefetch 2000']);
  });

  test('a fetch soon after the ask names fetch after turn', () async {
    final c = Completer<int>();
    probe.asked(8, c.future);
    clock = clock.add(const Duration(milliseconds: 200));
    probe.started(8);
    await settle(c, const Duration(seconds: 1));
    expect(slow, ['8 fetch after turn 1200']);
  });

  test('a page that waited mostly for its turn names queue', () async {
    final c = Completer<int>();
    probe.asked(4, c.future);
    clock = clock.add(const Duration(seconds: 2));
    probe.started(4);
    await settle(c, const Duration(milliseconds: 500));
    expect(slow, ['4 queue 2500']);
  });

  test('a page that never started names queue', () async {
    final c = Completer<int>();
    probe.asked(5, c.future);
    await settle(c, const Duration(seconds: 1));
    expect(slow, ['5 queue 1000']);
  });

  test('times from the first ask; asks while waiting join it', () async {
    final c = Completer<int>();
    probe
      ..started(1)
      ..asked(1, c.future);
    clock = clock.add(const Duration(milliseconds: 600));
    probe.asked(1, c.future);
    await settle(c, const Duration(milliseconds: 600));
    expect(slow, ['1 fetch after turn 1200']);
  });

  test('a failed fetch is timed too, and a retry times anew', () async {
    final c = Completer<int>();
    probe
      ..started(2)
      ..asked(2, c.future);
    clock = clock.add(const Duration(seconds: 1));
    c.completeError(StateError('boom'));
    await pumpEventQueue();
    expect(slow, ['2 fetch after turn 1000']);
    final again = Completer<int>();
    probe
      ..started(2)
      ..asked(2, again.future);
    await settle(again, const Duration(milliseconds: 10));
    expect(slow, ['2 fetch after turn 1000']);
  });

  test('bucket rounds down to 1, 2, 4 or 8 s', () {
    expect(
      [
        for (final ms in [1000, 1999, 2000, 4100, 9000, 60000])
          PageWaitProbe.bucket(Duration(milliseconds: ms)),
      ],
      ['over 1 s', 'over 1 s', 'over 2 s', 'over 4 s', 'over 8 s', 'over 8 s'],
    );
  });
}
