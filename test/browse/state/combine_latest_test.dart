import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/combine_latest.dart';

void main() {
  test('waits for both, then emits on every change', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final out = <String>[];
    final sub = combineLatest2(
      a.stream,
      b.stream,
      (x, y) => '$x$y',
    ).listen(out.add);
    a.add(1);
    await pumpEvents();
    expect(out, isEmpty);
    b.add('a');
    await pumpEvents();
    a.add(2);
    await pumpEvents();
    b.add('b');
    await pumpEvents();
    expect(out, ['1a', '2a', '2b']);
    await sub.cancel();
  });

  test('forwards errors and closes when both inputs are done', () async {
    final errors = <Object>[];
    var closed = false;
    final done = Completer<void>();
    combineLatest2(
      Stream<int>.error(StateError('x')),
      Stream.value(1),
      (x, y) => x + y,
    ).listen(
      (_) {},
      onError: errors.add,
      onDone: () {
        closed = true;
        done.complete();
      },
    );
    await done.future;
    expect(errors.single, isA<StateError>());
    expect(closed, isTrue);
  });
}

Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
