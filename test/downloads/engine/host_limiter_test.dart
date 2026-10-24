import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/downloads/engine/host_limiter.dart';

void main() {
  test('hostOf extracts the lowercase host, empty for non-URLs', () {
    expect(hostOf('https://Uploads.MangaDex.org/a/b.png'), 'uploads.mangadex.org');
    expect(hostOf('not a url'), '');
  });

  test('never runs more than perHost jobs on one host at a time', () async {
    final limiter = HostLimiter(perHost: 2);
    var running = 0;
    var peak = 0;
    final gates = List.generate(5, (_) => Completer<void>());
    final jobs = [
      for (final g in gates)
        limiter.run('a.example', () async {
          running++;
          peak = running > peak ? running : peak;
          await g.future;
          running--;
          return 1;
        }),
    ];
    await pumpEventQueue();
    expect(running, 2);
    for (final g in gates) {
      g.complete();
      await pumpEventQueue();
    }
    expect(await Future.wait(jobs), [1, 1, 1, 1, 1]);
    expect(peak, 2);
    expect(limiter.active('a.example'), 0);
  });

  test('different hosts do not block each other', () async {
    final limiter = HostLimiter(perHost: 1);
    final gate = Completer<void>();
    final slow = limiter.run('a', () => gate.future);
    final fast = await limiter.run('b', () async => 'b done');
    expect(fast, 'b done');
    gate.complete();
    await slow;
  });

  test('a failing job releases its slot', () async {
    final limiter = HostLimiter(perHost: 1);
    await expectLater(
      limiter.run<void>('a', () async => throw StateError('x')),
      throwsStateError,
    );
    expect(await limiter.run('a', () async => 2), 2);
  });
}
