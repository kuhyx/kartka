import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/downloads/engine/retry.dart';

void main() {
  group('RetryPolicy.delayFor', () {
    test('grows exponentially and caps at max', () {
      const p = RetryPolicy(
        maxAttempts: 6,
        base: Duration(milliseconds: 100),
        max: Duration(milliseconds: 500),
      );
      expect(p.delayFor(1), const Duration(milliseconds: 100));
      expect(p.delayFor(2), const Duration(milliseconds: 200));
      expect(p.delayFor(3), const Duration(milliseconds: 400));
      expect(p.delayFor(4), const Duration(milliseconds: 500));
    });
  });

  group('retry', () {
    test('returns the first success and sleeps between failures', () async {
      final sleeps = <Duration>[];
      var calls = 0;
      final value = await retry(
        () async {
          calls++;
          if (calls < 3) throw StateError('boom $calls');
          return 'ok';
        },
        policy: const RetryPolicy(maxAttempts: 3),
        sleep: (d) async => sleeps.add(d),
      );
      expect(value, 'ok');
      expect(calls, 3);
      expect(sleeps, const [Duration(seconds: 1), Duration(seconds: 2)]);
    });

    test('rethrows the last error after maxAttempts', () async {
      var calls = 0;
      await expectLater(
        retry<void>(
          () async {
            calls++;
            throw StateError('boom $calls');
          },
          policy: const RetryPolicy(maxAttempts: 2),
          sleep: (_) async {},
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom 2'),
        ),
      );
      expect(calls, 2);
    });

    test('does not retry when shouldRetry says no', () async {
      var calls = 0;
      await expectLater(
        retry<void>(
          () async {
            calls++;
            throw ArgumentError('fatal');
          },
          shouldRetry: (e) => e is! ArgumentError,
          sleep: (_) async {},
        ),
        throwsArgumentError,
      );
      expect(calls, 1);
    });

    test('default sleep waits for real', () async {
      final sw = Stopwatch()..start();
      var calls = 0;
      await retry(() async {
        if (calls++ == 0) throw StateError('once');
        return 1;
      }, policy: const RetryPolicy(base: Duration(milliseconds: 20)));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(20));
    });
  });
}
