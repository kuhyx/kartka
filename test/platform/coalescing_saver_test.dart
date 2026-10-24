import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/coalescing_saver.dart';

void main() {
  test('N schedules inside the window become one save', () {
    fakeAsync((async) {
      var saves = 0;
      final saver = CoalescingSaver(() async => saves++);
      for (var i = 0; i < 50; i++) {
        saver.schedule();
        async.elapse(const Duration(milliseconds: 4));
      }
      expect(saves, 0);
      expect(saver.pending, isTrue);
      async.elapse(const Duration(milliseconds: 60));
      expect(saves, 1);
      expect(saver.pending, isFalse);
      async.elapse(const Duration(seconds: 5));
      expect(saves, 1);
    });
  });

  test('latency is bounded: a steady stream still saves every window', () {
    fakeAsync((async) {
      var saves = 0;
      final saver = CoalescingSaver(() async => saves++);
      for (var i = 0; i < 100; i++) {
        saver.schedule();
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(saves, 4);
    });
  });

  test('flush saves at once, and is a no-op when clean', () {
    fakeAsync((async) {
      var saves = 0;
      final saver = CoalescingSaver(() async => saves++);
      unawaited(saver.flush());
      async.flushMicrotasks();
      expect(saves, 0);
      saver.schedule();
      unawaited(saver.flush());
      async.flushMicrotasks();
      expect(saves, 1);
      async.elapse(const Duration(seconds: 1));
      expect(saves, 1);
    });
  });

  test('a change during an in-flight save is saved after it', () {
    fakeAsync((async) {
      var saves = 0;
      final gate = Completer<void>();
      final saver = CoalescingSaver(() async {
        saves++;
        if (saves == 1) await gate.future;
      })..schedule();
      unawaited(saver.flush());
      async.flushMicrotasks();
      saver.schedule();
      var second = false;
      unawaited(saver.flush().then((_) => second = true));
      async.flushMicrotasks();
      expect((saves, second), (1, false));
      gate.complete();
      async.flushMicrotasks();
      expect((saves, second), (2, true));
    });
  });

  test('a failed save stays dirty and is retried by the next flush', () {
    fakeAsync((async) {
      var calls = 0;
      final saver = CoalescingSaver(() async {
        if (++calls == 1) throw StateError('disk full');
      })..schedule();
      async.elapse(const Duration(milliseconds: 300));
      expect((calls, saver.pending), (1, true));
      Object? error;
      unawaited(saver.flush().catchError((Object e) => error = e));
      async.flushMicrotasks();
      expect((calls, saver.pending, error), (2, false, null));
    });
  });

  testWidgets('flushOnBackground flushes when the app leaves the foreground', (
    tester,
  ) async {
    var flushes = 0;
    final listener = flushOnBackground(() async => flushes++);
    addTearDown(listener.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(flushes, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(flushes, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    expect(flushes, 9);
  });
}
