import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/shown_page_gate.dart';
import 'package:kartka/reader/logic/shown_page_wait.dart';

/// The shown-page gate (28fffd0a): background work on a source waits
/// while the reader's shown page is still loading, never longer than
/// [ShownPageWait.maxHold].
void main() {
  test('idle at once with no shown page pending', () {
    fakeAsync((async) {
      final ShownPageGate gate = ShownPageWait();
      var done = false;
      unawaited(gate.idle().then((_) => done = true));
      async.flushMicrotasks();
      expect(done, isTrue);
    });
  });

  test('waits for every held page, failed ones too', () {
    fakeAsync((async) {
      final wait = ShownPageWait();
      final a = Completer<int>();
      final b = Completer<int>();
      wait
        ..hold(a.future)
        ..hold(b.future);
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

  test('a stuck page holds work back at most maxHold', () {
    fakeAsync((async) {
      final wait = ShownPageWait()..hold(Completer<int>().future);
      var done = false;
      unawaited(wait.idle().then((_) => done = true));
      async.elapse(const Duration(milliseconds: 2999));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });
}
