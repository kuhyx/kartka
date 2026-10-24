import 'dart:collection';

/// Waits for [duration]; injectable so tests run on a fake clock.
typedef Sleep = Future<void> Function(Duration duration);

const _window = Duration(minutes: 1);

/// Sliding-window client-side limiter for tracker APIs.
///
/// Keeps at most [perMinute] requests in any 60 s window, spaces requests by
/// [minGap] (burst limiter), and obeys the server's own `Retry-After` and
/// `X-RateLimit-Remaining` signals reported through [observe].
class RateLimiter {
  /// Creates a limiter allowing [perMinute] requests per rolling minute.
  new({
    required this.perMinute,
    this.minGap = const Duration(milliseconds: 500),
    DateTime Function()? now,
    Sleep? sleep,
  }) : _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed {
    if (perMinute <= 0) {
      throw ArgumentError.value(perMinute, 'perMinute', 'must be positive');
    }
  }

  /// Request budget per rolling minute.
  final int perMinute;

  /// Minimum spacing between two requests.
  final Duration minGap;

  final DateTime Function() _now;
  final Sleep _sleep;
  final Queue<DateTime> _sent = Queue();
  DateTime? _blockedUntil;
  Future<void> _tail = Future.value();

  /// Completes when a request may be sent, and books its slot.
  Future<void> acquire() {
    final next = _tail.then((_) => _acquireOne());
    _tail = next;
    return next;
  }

  /// Feeds the server's view back in after each response.
  void observe({int? remaining, Duration? retryAfter}) {
    final now = _now();
    if (retryAfter != null) _block(now.add(retryAfter));
    if (remaining != null && remaining <= 0) {
      _block((_sent.isEmpty ? now : _sent.first).add(_window));
    }
  }

  void _block(DateTime until) {
    final current = _blockedUntil;
    if (current == null || until.isAfter(current)) _blockedUntil = until;
  }

  Future<void> _acquireOne() async {
    await _waitUntil(_earliestSlot());
    final now = _now();
    _sent.addLast(now);
    while (_sent.length > perMinute) {
      _sent.removeFirst();
    }
  }

  DateTime _earliestSlot() {
    var at = _now();
    DateTime later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
    final blocked = _blockedUntil;
    if (blocked != null) at = later(at, blocked);
    if (_sent.isNotEmpty) at = later(at, _sent.last.add(minGap));
    if (_sent.length >= perMinute) at = later(at, _sent.first.add(_window));
    return at;
  }

  Future<void> _waitUntil(DateTime at) async {
    final wait = at.difference(_now());
    if (wait > Duration.zero) await _sleep(wait);
    final blocked = _blockedUntil;
    if (blocked != null && !_now().isBefore(blocked)) _blockedUntil = null;
  }
}
