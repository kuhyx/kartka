import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/suwayomi/search_slots.dart';

void main() {
  test('at most [size] jobs run at once; the rest wait their turn', () async {
    final slots = SearchSlots(2);
    final gates = [for (var i = 0; i < 4; i++) Completer<int>()];
    var running = 0;
    var most = 0;
    final done = [
      for (final g in gates)
        slots.run(() async {
          running++;
          most = running > most ? running : most;
          try {
            return await g.future;
          } finally {
            running--;
          }
        }),
    ];
    await pumpEventQueue();
    expect(running, 2);
    for (final (i, g) in gates.indexed) {
      g.complete(i);
      await pumpEventQueue();
    }
    expect(await Future.wait(done), [0, 1, 2, 3]);
    expect(most, 2);
  });

  test('a failing job frees its slot', () async {
    final slots = SearchSlots(1);
    await expectLater(
      slots.run(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(await slots.run(() async => 7), 7);
  });
}
