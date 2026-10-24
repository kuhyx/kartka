import 'dart:async';
import 'dart:collection';

/// At most [max] requests per [per] to [host] (optionally only paths that
/// start with [pathPrefix]).
class RateRule {
  /// Creates a rule.
  const new({
    required this.host,
    required this.max,
    required this.per,
    this.pathPrefix,
  });

  /// Host the rule applies to.
  final String host;

  /// Limits only paths with this prefix; null means the whole host.
  final String? pathPrefix;

  /// Requests allowed per window.
  final int max;

  /// Window length.
  final Duration per;

  /// Whether a request to [uri] counts against this rule.
  bool matches(Uri uri) =>
      uri.host == host && uri.path.startsWith(pathPrefix ?? '');
}

/// MangaDex's documented limits: about 5 req/s per IP on the API, and
/// 40/min on `GET /at-home/server/{id}` on top of that.
const mangadexRateRules = [
  RateRule(host: 'api.mangadex.org', max: 5, per: Duration(seconds: 1)),
  RateRule(
    host: 'api.mangadex.org',
    pathPrefix: '/at-home/server/',
    max: 40,
    per: Duration(minutes: 1),
  ),
];

/// Sliding-window limiter; callers are granted one at a time, in order.
class RateLimiter {
  /// Creates a limiter; [now] and [delay] are injectable for tests.
  new(
    this.rules, {
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// Rules in force.
  final List<RateRule> rules;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Map<RateRule, Queue<DateTime>> _grants = {};
  final Map<String, DateTime> _blockedUntil = {};
  Future<void> _tail = Future.value();

  /// Completes when a request to [uri] may be sent.
  Future<void> acquire(Uri uri) {
    final turn = _tail.then((_) => _grant(uri));
    _tail = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  /// Blocks [host] until [until], e.g. from a 429's `X-RateLimit-Retry-After`.
  void backOff(String host, DateTime until) => _blockedUntil[host] = until;

  Future<void> _grant(Uri uri) async {
    final matching = [
      for (final r in rules)
        if (r.matches(uri)) r,
    ];
    for (;;) {
      final wait = _waitFor(uri.host, matching);
      if (wait <= Duration.zero) break;
      await _delay(wait);
    }
    final at = _now();
    for (final r in matching) {
      (_grants[r] ??= Queue()).addLast(at);
    }
  }

  Duration _waitFor(String host, List<RateRule> matching) {
    final now = _now();
    var wait = (_blockedUntil[host] ?? now).difference(now);
    for (final r in matching) {
      final q = _grants[r] ??= Queue();
      while (q.isNotEmpty && !now.isBefore(q.first.add(r.per))) {
        q.removeFirst();
      }
      if (q.length < r.max) continue;
      final free = q.first.add(r.per).difference(now);
      if (free > wait) wait = free;
    }
    return wait;
  }
}
