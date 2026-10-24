import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';

/// Deterministic clock: `sleep` advances time and records every wait.
class FakeClock {
  DateTime now = DateTime.utc(2026, 10, 24, 12);
  final List<Duration> waits = [];

  DateTime read() => now;

  Future<void> sleep(Duration d) async {
    waits.add(d);
    now = now.add(d);
  }
}

RateLimiter limiter(FakeClock c, {int perMinute = 3, Duration? minGap}) =>
    RateLimiter(
      perMinute: perMinute,
      minGap: minGap ?? Duration.zero,
      now: c.read,
      sleep: c.sleep,
    );

void main() {
  test('lets the first perMinute requests through without waiting', () async {
    final c = FakeClock();
    final l = limiter(c);
    for (var i = 0; i < 3; i++) {
      await l.acquire();
    }
    expect(c.waits, isEmpty);
  });

  test('waits for the oldest slot to leave the 60 s window', () async {
    final c = FakeClock();
    final l = limiter(c);
    await l.acquire();
    c.now = c.now.add(const Duration(seconds: 10));
    await l.acquire();
    await l.acquire();
    await l.acquire();
    expect(c.waits, [const Duration(seconds: 50)]);
  });

  test('enforces the minimum gap between requests', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 30, minGap: const Duration(seconds: 1));
    await l.acquire();
    await l.acquire();
    expect(c.waits, [const Duration(seconds: 1)]);
  });

  test('Retry-After blocks the next acquire', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 30)
      ..observe(retryAfter: const Duration(seconds: 30));
    await l.acquire();
    expect(c.waits, [const Duration(seconds: 30)]);
  });

  test('remaining 0 waits for the window to slide', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 30);
    await l.acquire();
    l.observe(remaining: 0);
    await l.acquire();
    expect(c.waits, [const Duration(seconds: 60)]);
  });

  test('remaining 0 with no history waits a full window', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 30)..observe(remaining: 0);
    await l.acquire();
    expect(c.waits, [const Duration(seconds: 60)]);
  });

  test('positive remaining does not block', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 30)..observe(remaining: 5);
    await l.acquire();
    expect(c.waits, isEmpty);
  });

  test('concurrent acquires are serialised', () async {
    final c = FakeClock();
    final l = limiter(c, perMinute: 1);
    await Future.wait([l.acquire(), l.acquire()]);
    expect(c.waits, [const Duration(seconds: 60)]);
  });

  test('defaults use the real clock', () async {
    final l = RateLimiter(perMinute: 2);
    await l.acquire();
    expect(l.perMinute, 2);
  });

  test('rejects a non-positive budget', () {
    expect(() => RateLimiter(perMinute: 0), throwsArgumentError);
  });
}
