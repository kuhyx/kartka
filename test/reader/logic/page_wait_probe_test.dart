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

  test('a fetch started at the turn names turn', () async {
    final c = Completer<int>();
    probe.started(3);
    clock = clock.add(const Duration(milliseconds: 249));
    probe.asked(3, c.future);
    await settle(c, const Duration(milliseconds: 1500));
    expect(slow, ['3 turn 1500']);
  });

  test('a page prefetched well before the turn names prefetch', () async {
    final c = Completer<int>();
    probe.started(7);
    clock = clock.add(const Duration(milliseconds: 250));
    probe.asked(7, c.future);
    await settle(c, const Duration(seconds: 2));
    expect(slow, ['7 prefetch 2000']);
  });

  test('a fetch soon after the ask names turn', () async {
    final c = Completer<int>();
    probe.asked(8, c.future);
    clock = clock.add(const Duration(milliseconds: 200));
    probe.started(8);
    await settle(c, const Duration(seconds: 1));
    expect(slow, ['8 turn 1200']);
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
    expect(slow, ['1 turn 1200']);
  });

  test('a failed fetch is timed too, and a retry times anew', () async {
    final c = Completer<int>();
    probe
      ..started(2)
      ..asked(2, c.future);
    clock = clock.add(const Duration(seconds: 1));
    c.completeError(StateError('boom'));
    await pumpEventQueue();
    expect(slow, ['2 turn 1000']);
    final again = Completer<int>();
    probe
      ..started(2)
      ..asked(2, again.future);
    await settle(again, const Duration(milliseconds: 10));
    expect(slow, ['2 turn 1000']);
  });

  test('the open and the advance name their own step', () async {
    final open = Completer<int>();
    final next = Completer<int>();
    probe
      ..started(0)
      ..asked(0, open.future, edge: 'open')
      ..started(9)
      ..asked(9, next.future, edge: 'advance');
    await settle(open, const Duration(seconds: 1));
    next.complete(1);
    await pumpEventQueue();
    expect(slow, ['0 open 1000', '9 advance 1000']);
  });

  test('a prefetched or queued edge page keeps its step', () async {
    final c = Completer<int>();
    probe.started(6);
    clock = clock.add(const Duration(seconds: 1));
    probe.asked(6, c.future, edge: 'advance');
    await settle(c, const Duration(seconds: 1));
    expect(slow, ['6 prefetch 1000']);
  });

  test('joining a warm names warm, timed from the warm', () async {
    final c = Completer<int>();
    final began = clock;
    clock = clock.add(const Duration(milliseconds: 100));
    probe
      ..started(2, at: began, warm: true)
      ..asked(2, c.future, edge: 'open');
    await settle(c, const Duration(seconds: 2));
    expect(slow, ['2 warm 2000']);
  });

  test('a true start well before the ask names prefetch', () async {
    final c = Completer<int>();
    final began = clock;
    clock = clock.add(const Duration(seconds: 1));
    probe
      ..started(3, at: began)
      ..asked(3, c.future);
    await settle(c, const Duration(seconds: 1));
    expect(slow, ['3 prefetch 1000']);
  });

  test('domain keeps the last two host labels; a stored page is storage', () {
    expect(
      [
        for (final url in [
          'https://cmdxd98sb0x3yprd.mangadex.network:443/data/a/1.png',
          'https://uploads.mangadex.org/data/a/1.png',
          'https://img.test/c/2/0.png',
          'http://127.0.0.1:4567/api/v1/manga/5/chapter/2/page/0',
          'blob-key/chapter/0',
        ])
          PageWaitProbe.domain(url),
      ],
      ['mangadex.network', 'mangadex.org', 'img.test', '127.0.0.1', 'storage'],
    );
  });
}
