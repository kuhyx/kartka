import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';

void main() {
  late List<int> recorded;
  late int markedRead;
  ProgressRecorder make({int pageCount = 5}) => ProgressRecorder(
    pageCount: pageCount,
    debounce: const Duration(milliseconds: 500),
    record: (page) async => recorded.add(page),
    markRead: () async => markedRead++,
  );

  setUp(() {
    recorded = [];
    markedRead = 0;
  });

  test('page changes are debounced to the last one', () {
    fakeAsync((async) {
      make()
        ..onPage(0)
        ..onPage(1)
        ..onPage(2);
      async.elapse(const Duration(milliseconds: 499));
      expect(recorded, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(recorded, [2]);
      expect(markedRead, 0);
    });
  });

  test('the same page twice is recorded once', () {
    fakeAsync((async) {
      final r = make()..onPage(1);
      async.elapse(const Duration(seconds: 1));
      r.onPage(1);
      async.elapse(const Duration(seconds: 1));
      expect(recorded, [1]);
    });
  });

  test('reaching the last page records immediately and marks read once', () {
    fakeAsync((async) {
      final r = make()..onPage(4);
      async.flushMicrotasks();
      expect(recorded, [4]);
      expect(markedRead, 1);
      r.onPage(3);
      async.elapse(const Duration(seconds: 1));
      r.onPage(4);
      async.flushMicrotasks();
      expect(recorded, [4, 3, 4]);
      expect(markedRead, 1);
    });
  });

  test('flush writes the pending page, dispose drops nothing silently', () {
    fakeAsync((async) {
      final r = make()..onPage(2);
      unawaited(r.flush());
      async.flushMicrotasks();
      expect(recorded, [2]);
      r
        ..onPage(3)
        ..dispose();
      async.flushMicrotasks();
      expect(recorded, [2, 3]);
      r.onPage(1);
      async.elapse(const Duration(seconds: 1));
      expect(recorded, [2, 3]);
    });
  });

  test('flush with nothing pending is a no-op', () async {
    await make().flush();
    expect(recorded, isEmpty);
  });

  test('out-of-range pages are ignored', () {
    fakeAsync((async) {
      make()
        ..onPage(-1)
        ..onPage(5);
      async.elapse(const Duration(seconds: 1));
      expect(recorded, isEmpty);
    });
  });
}
