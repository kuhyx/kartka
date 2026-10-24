/// Foreground-only polling (contracts §12): every 5 s while the app is
/// resumed, nothing while it is in the background.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [poll] every [interval] while the app lifecycle is resumed.
class SyncScheduler with WidgetsBindingObserver {
  /// Creates a stopped scheduler.
  new(this.poll, {this.interval = const Duration(seconds: 5)});

  /// One cheap change check (`SyncEngine.poll`).
  final Future<void> Function() poll;

  /// Poll period; 5 s keeps cross-device latency under the 10 s goal.
  final Duration interval;

  Timer? _timer;
  bool _attached = false;
  bool _busy = false;

  /// Whether a poll timer is running.
  bool get running => _timer != null;

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
      _stop();
    }
  }

  void _start() {
    if (_timer != null) return;
    _fire();
    _timer = Timer.periodic(interval, (_) => _fire());
  }

  /// Skips a tick while the previous poll still runs, so a slow network
  /// never queues up a backlog of polls.
  void _fire() {
    if (_busy) return;
    _busy = true;
    unawaited(poll().whenComplete(() => _busy = false));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}
