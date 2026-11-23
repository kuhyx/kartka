import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/shown_page_gate.dart';
import 'package:kartka/reader/logic/shown_page_wait.dart';

/// The shown-page gate (28fffd0a): background work on a source waits
/// while the reader's shown page is still loading, never longer than
/// [ShownPageWait.maxHold] after that page started.
void main() {
  final t0 = DateTime.utc(2026, 11, 23);
  ShownPageWait timed(FakeAsync async) =>
      ShownPageWait(now: () => t0.add(async.elapsed));

  test('idle at once with no shown page pending', () {
    fakeAsync((async) {
      final ShownPageGate gate = timed(async);
      var done = false;
      unawaited(gate.idle().then((_) => done = true));
      async.flushMicrotasks();
      expect(done, isTrue);
    });
  });

  test('waits for every held page, failed ones too', () {
    fakeAsync((async) {
      final wait = timed(async);
      final a = Completer<int>();
      final b = Completer<int>();
      wait
        ..hold(1, a.future)
        ..hold(1, b.future);
      expect(wait.busy, isTrue);
      var done = false;
      unawaited(wait.idle().then((_) => done = true));
      a.complete(1);
      async.flushMicrotasks();
      expect(done, isFalse);
      b.completeError(StateError('boom'));
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(wait.busy, isFalse);
    });
  });

  test('a stuck page holds work back maxHold from its start, in all', () {
    fakeAsync((async) {
      final wait = timed(async)..hold(1, Completer<int>().future);
      final done = <int>[];
      unawaited(wait.idle().then((_) => done.add(1)));
      async.elapse(const Duration(seconds: 2));
      unawaited(wait.idle().then((_) => done.add(2)));
      async.elapse(const Duration(milliseconds: 999));
      expect(done, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, [1, 2]);
      unawaited(wait.idle().then((_) => done.add(3)));
      async.flushMicrotasks();
      expect(done, [1, 2, 3]);
    });
  });

  test('a newer shown page holds work back from its own start', () {
    fakeAsync((async) {
      final wait = timed(async)..hold(1, Completer<int>().future);
      async.elapse(const Duration(seconds: 5));
      wait.hold(1, Completer<int>().future);
      var done = false;
      unawaited(wait.idle().then((_) => done = true));
      async.elapse(const Duration(milliseconds: 2999));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });

  test("releasing an owner drops only that owner's holds", () {
    fakeAsync((async) {
      final wait = timed(async);
      final other = Completer<int>();
      wait
        ..hold(1, Completer<int>().future)
        ..hold(2, other.future)
        ..releaseAll(1);
      expect(wait.busy, isTrue);
      var done = false;
      unawaited(wait.idle().then((_) => done = true));
      other.complete(1);
      async.flushMicrotasks();
      expect(done, isTrue);
      wait.releaseAll(1);
      expect(wait.busy, isFalse);
    });
  });
}
