import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/mangadex/rate_limiter.dart';

/// A clock that only moves when the limiter sleeps.
class FakeClock {
  DateTime now = DateTime.utc(2026, 10, 24, 12);
  final List<Duration> waits = [];

  Future<void> delay(Duration d) async {
    waits.add(d);
    now = now.add(d);
  }
}

void main() {
  late FakeClock clock;
  late RateLimiter limiter;
  final api = Uri.parse('https://api.mangadex.org/manga');
  final atHome = Uri.parse('https://api.mangadex.org/at-home/server/x');
  final other = Uri.parse('https://uploads.mangadex.org/covers/a.jpg');

  setUp(() {
    clock = FakeClock();
    limiter = RateLimiter(
      mangadexRateRules,
      now: () => clock.now,
      delay: clock.delay,
    );
  });

  test('five api calls in a second pass, the sixth waits', () async {
    for (var i = 0; i < 5; i++) {
      await limiter.acquire(api);
    }
    expect(clock.waits, isEmpty);
    await limiter.acquire(api);
    expect(clock.waits, [const Duration(seconds: 1)]);
  });

  test('requests spread in time never wait', () async {
    for (var i = 0; i < 12; i++) {
      await limiter.acquire(api);
      clock.now = clock.now.add(const Duration(milliseconds: 250));
    }
    expect(clock.waits, isEmpty);
  });

  test('at-home has its own 40 per minute bucket', () async {
    for (var i = 0; i < 40; i++) {
      await limiter.acquire(atHome);
      clock.now = clock.now.add(const Duration(milliseconds: 300));
    }
    expect(clock.waits, isEmpty);
    await limiter.acquire(atHome);
    expect(clock.waits.single, const Duration(seconds: 48));
  });

  test('unmatched hosts are not limited', () async {
    for (var i = 0; i < 20; i++) {
      await limiter.acquire(other);
    }
    expect(clock.waits, isEmpty);
  });

  test('concurrent callers are served one after another', () async {
    await Future.wait([for (var i = 0; i < 10; i++) limiter.acquire(api)]);
    expect(clock.waits, [const Duration(seconds: 1)]);
  });

  test('backOff blocks a host until the given instant', () async {
    limiter.backOff(
      'api.mangadex.org',
      clock.now.add(const Duration(seconds: 7)),
    );
    await limiter.acquire(other);
    expect(clock.waits, isEmpty);
    await limiter.acquire(api);
    expect(clock.waits, [const Duration(seconds: 7)]);
    await limiter.acquire(api);
    expect(clock.waits, hasLength(1));
  });

  test('a failing delay does not wedge later callers', () async {
    var fail = true;
    final l = RateLimiter(
      const [RateRule(host: 'h', max: 1, per: Duration(seconds: 1))],
      now: () => clock.now,
      delay: (d) async {
        if (fail) {
          fail = false;
          throw StateError('boom');
        }
        await clock.delay(d);
      },
    );
    final u = Uri.parse('https://h/x');
    await l.acquire(u);
    await expectLater(l.acquire(u), throwsStateError);
    await l.acquire(u);
    expect(clock.waits, [const Duration(seconds: 1)]);
  });

  test('defaults use the wall clock', () async {
    final l = RateLimiter(const []);
    await l.acquire(api);
  });
}
