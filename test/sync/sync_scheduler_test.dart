import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/sync_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Seconds (since attach) at which each poll started, over [span].
  List<int> pollTimes(
    FakeAsync async,
    SyncScheduler Function(void Function() onPoll) make, {
    Duration span = const Duration(minutes: 3),
  }) {
    final at = <int>[];
    final start = async.elapsed;
    final s = make(() => at.add((async.elapsed - start).inSeconds))..attach();
    async.elapse(span);
    s.detach();
    return at;
  }

  test('defaults: 5 s in the foreground, backoff capped at 60 s', () {
    final s = SyncScheduler(() async {});
    expect(s.interval, const Duration(seconds: 5));
    expect(s.maxInterval, const Duration(seconds: 60));
  });

  test('a healthy foreground polls every 5 s (inside the 10 s goal)', () {
    fakeAsync((async) {
      final at = pollTimes(
        async,
        (onPoll) => SyncScheduler(() async => onPoll()),
        span: const Duration(seconds: 21),
      );
      expect(at, [0, 5, 10, 15, 20]);
    });
  });

  test('failing polls back off 5, 10, 20, 40, then 60 s', () {
    fakeAsync((async) {
      final at = pollTimes(
        async,
        (onPoll) => SyncScheduler(() async => onPoll(), ok: () => false),
      );
      expect(at, [0, 5, 15, 35, 75, 135]);
    });
  });

  test('a throwing poll counts as a failure and keeps the loop alive', () {
    fakeAsync((async) {
      final at = pollTimes(
        async,
        (onPoll) => SyncScheduler(() async {
          onPoll();
          throw StateError('boom');
        }),
        span: const Duration(seconds: 40),
      );
      expect(at, [0, 5, 15, 35]);
    });
  });

  test('one success resets the backoff', () {
    fakeAsync((async) {
      var healthy = false;
      final at = <int>[];
      final s = SyncScheduler(
        () async => at.add(async.elapsed.inSeconds),
        ok: () => healthy,
      )..attach();
      async.elapse(const Duration(seconds: 16));
      expect(at, [0, 5, 15]);
      healthy = true;
      async.elapse(const Duration(seconds: 30));
      expect(at, [0, 5, 15, 35, 40, 45]);
      s.detach();
    });
  });

  test('kick (signed in) polls now and forgets the backoff', () {
    fakeAsync((async) {
      var healthy = false;
      final at = <int>[];
      final s = SyncScheduler(
        () async => at.add(async.elapsed.inSeconds),
        ok: () => healthy,
      )..kick();
      expect(at, isEmpty, reason: 'stopped: nothing to kick');
      s.attach();
      async.elapse(const Duration(seconds: 16));
      healthy = true;
      s.kick();
      async.elapse(const Duration(seconds: 6));
      expect(at, [0, 5, 15, 16, 21]);
      s.detach();
    });
  });

  test('kicks and resumes during a hung poll start no second poll', () {
    fakeAsync((async) {
      var started = 0;
      final hung = Completer<void>();
      final s = SyncScheduler(() {
        started++;
        return started == 1 ? hung.future : Future<void>.value();
      })..attach();
      for (var i = 0; i < 3; i++) {
        s
          ..kick()
          ..didChangeAppLifecycleState(AppLifecycleState.inactive)
          ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      async.elapse(const Duration(seconds: 30));
      expect(started, 1, reason: 'every restart waits for the hung poll');
      hung.complete();
      async.elapse(const Duration(seconds: 6));
      expect(started, 2, reason: 'one loop resumes after it');
      s.detach();
    });
  });

  test('resume polls at once and forgets the backoff', () {
    fakeAsync((async) {
      final at = <int>[];
      final s = SyncScheduler(
        () async => at.add(async.elapsed.inSeconds),
        ok: () => false,
      )..attach();
      async.elapse(const Duration(seconds: 16));
      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.elapse(const Duration(seconds: 100));
      expect(at, [0, 5, 15], reason: 'nothing while backgrounded');
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.elapse(const Duration(seconds: 6));
      expect(at, [0, 5, 15, 116, 121]);
      s.detach();
    });
  });
}
