import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/migration/first_value.dart';

void main() {
  test('the first event, then the subscription is cancelled', () async {
    var cancelled = false;
    final c = StreamController<int>(onCancel: () => cancelled = true);
    final first = firstValue(c.stream);
    c
      ..add(1)
      ..add(2);
    expect(await first, 1);
    expect(cancelled, isTrue);
  });

  test('a stream that emits inside listen is cancelled too', () async {
    final eager = _Eager();
    expect(await firstValue(eager), 7);
    expect(eager.cancelled, isTrue);
  });

  test('an error first is the error; a second one is ignored', () async {
    final c = StreamController<int>();
    final first = firstValue(c.stream);
    c
      ..addError(StateError('boom'))
      ..addError(StateError('again'));
    await expectLater(first, throwsStateError);
  });

  test('an empty stream has no element', () async {
    await expectLater(firstValue(const Stream<int>.empty()), throwsStateError);
  });
}

/// Delivers its value inside `listen`, before the subscription is returned.
class _Eager extends Stream<int> {
  bool cancelled = false;

  @override
  StreamSubscription<int> listen(
    void Function(int)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onData!(7);
    final c = StreamController<int>(onCancel: () => cancelled = true);
    return c.stream.listen(null);
  }
}
