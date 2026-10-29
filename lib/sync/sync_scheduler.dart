/// Foreground-only polling (contracts §12): every 5 s while the app is
/// resumed and polls succeed, nothing while it is in the background.
///
/// Why 5 s and not slower when idle: progress pushes wait up to 3.6 s
/// (0.6 s page debounce + 3 s deferred push), and a peer then needs one
/// interval plus three RTDB reads, which must fit the 10 s cross-device
/// goal (DOCS-spec). A no-op poll is one tiny `revs` read and writes
/// nothing to storage, so it costs no UI-isolate time worth saving.
/// Failures (offline, signed out, server errors) back off instead:
/// 5, 10, 20, 40, then every 60 s, reset by a success or by resume.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Calls [poll] every [interval] while the app lifecycle is resumed.
class SyncScheduler with WidgetsBindingObserver {
  /// Creates a stopped scheduler; [ok] tells whether the last poll reached
  /// the server (always, when omitted).
  new(
    this.poll, {
    this.onPause,
    bool Function()? ok,
    this.interval = const Duration(seconds: 5),
    this.maxInterval = const Duration(seconds: 60),
  }) : _ok = ok ?? _always;

  static bool _always() => true;

  /// One cheap change check (`SyncEngine.poll`).
  final Future<void> Function() poll;

  /// Runs when the app leaves the foreground (flushes deferred pushes).
  final Future<void> Function()? onPause;

  /// Poll period while polls succeed; keeps cross-device latency < 10 s.
  final Duration interval;

  /// Longest wait between polls while they keep failing.
  final Duration maxInterval;

  final bool Function() _ok;
  Timer? _timer;
  bool _attached = false;
  bool _running = false;
  int _failures = 0;
  // Bumped by every start/stop, so a poll finishing after a stop (or a
  // stop + start) does not schedule a second loop.
  int _generation = 0;

  /// Whether foreground polling is on.
  bool get running => _running;

  /// Observes the lifecycle and starts polling if the app is in front.
  void attach() {
    if (_attached) return;
    _attached = true;
    final binding = WidgetsBinding.instance..addObserver(this);
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _start();
  }

  /// Stops polling and observing.
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      final wasRunning = running;
      _stop();
      final pause = onPause;
      if (wasRunning && pause != null) unawaited(pause());
    }
  }

  /// Polls now and forgets any backoff (after signing in), if running.
  void kick() {
    if (!_running) return;
    _stop();
    _start();
  }

  void _start() {
    if (_running) return;
    _running = true;
    _failures = 0;
    unawaited(_fire(++_generation));
  }

  /// Polls once, then waits [interval] (or the backoff) from its end, so a
  /// slow network never queues up a backlog of polls.
  Future<void> _fire(int generation) async {
    var healthy = false;
    try {
      await poll();
      healthy = _ok();
    } on Object {
      // The engine logs its own failures; here a throw only means backoff.
    }
    if (generation != _generation) return;
    _failures = healthy ? 0 : _failures + 1;
    _timer = Timer(_delay(), () => unawaited(_fire(generation)));
  }

  Duration _delay() {
    if (_failures == 0) return interval;
    final grown = interval * math.pow(2, math.min(_failures - 1, 16)).toInt();
    return grown > maxInterval ? maxInterval : grown;
  }

  void _stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
