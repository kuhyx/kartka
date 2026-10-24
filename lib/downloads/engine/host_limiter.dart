/// Per-host concurrency limit so one slow or strict site is never hammered.
library;

import 'dart:async';
import 'dart:collection';

/// Lowercase host of [url], or `''` when it has none.
String hostOf(String url) => (Uri.tryParse(url)?.host ?? '').toLowerCase();

/// A counting semaphore keyed by host.
class HostLimiter {
  /// At most [perHost] jobs run at once on any single host.
  HostLimiter({this.perHost = 2});

  /// Maximum concurrent jobs per host.
  final int perHost;

  final Map<String, int> _active = {};
  final Map<String, Queue<Completer<void>>> _waiting = {};

  /// Jobs currently running on [host].
  int active(String host) => _active[host] ?? 0;

  /// Runs [job] once a slot on [host] is free; the slot is always released.
  Future<T> run<T>(String host, Future<T> Function() job) async {
    if (active(host) >= perHost) {
      final turn = Completer<void>();
      _waiting.putIfAbsent(host, Queue.new).add(turn);
      await turn.future; // the releasing job hands its slot over directly
    } else {
      _active[host] = active(host) + 1;
    }
    try {
      return await job();
    } finally {
      _release(host);
    }
  }

  void _release(String host) {
    final queue = _waiting[host];
    if (queue != null && queue.isNotEmpty) {
      queue.removeFirst().complete();
      return;
    }
    _active[host] = active(host) - 1;
  }
}
