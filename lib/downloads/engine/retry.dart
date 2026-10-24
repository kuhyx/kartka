/// Retry with exponential backoff, used for every downloaded page.
library;

/// How often and how patiently a failed page is retried.
class RetryPolicy {
  /// Creates a policy; defaults are 4 attempts, 1 s doubling up to 30 s.
  const RetryPolicy({
    this.maxAttempts = 4,
    this.base = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
  });

  /// Total attempts including the first one.
  final int maxAttempts;

  /// Delay after the first failure.
  final Duration base;

  /// Upper bound for any single delay.
  final Duration max;

  /// Delay to wait after failed attempt number [attempt] (1-based).
  Duration delayFor(int attempt) {
    final ms = base.inMilliseconds * (1 << (attempt - 1));
    return ms > max.inMilliseconds ? max : Duration(milliseconds: ms);
  }
}

/// Sleeps for a duration; injectable so tests do not wait.
typedef Sleep = Future<void> Function(Duration delay);

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

/// Runs [action] until it succeeds, [policy] attempts are spent, or
/// [shouldRetry] rejects the error. The last error is rethrown.
Future<T> retry<T>(
  Future<T> Function() action, {
  RetryPolicy policy = const RetryPolicy(),
  bool Function(Object error) shouldRetry = _always,
  Sleep sleep = _realSleep,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } on Object catch (e) {
      if (attempt >= policy.maxAttempts || !shouldRetry(e)) rethrow;
      await sleep(policy.delayFor(attempt));
    }
  }
}

bool _always(Object _) => true;
