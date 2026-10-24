import 'dart:async';

import 'package:flutter/widgets.dart';

/// Coalesces many "state changed" signals into few calls of a save function.
///
/// The first [schedule] after a save starts a [window]-long timer; every
/// further [schedule] inside it rides along, so N changes cost one save and
/// a steady stream still saves once per window (a resetting debounce would
/// postpone forever). [flush] saves now and waits; the app calls it when it
/// leaves the foreground (see [flushOnBackground]), so a clean pause never
/// loses a change.
class CoalescingSaver {
  /// Calls [_save] at most once per [window] while changes keep coming.
  new(this._save, {this.window = const Duration(milliseconds: 250)});

  final Future<void> Function() _save;

  /// How long changes are collected before they are saved.
  final Duration window;

  Timer? _timer;
  bool _dirty = false;
  Future<void>? _running;

  /// Whether a change has not been saved yet.
  bool get pending => _dirty;

  /// Marks the state changed; it is saved within [window].
  void schedule() {
    _dirty = true;
    // A failed timer save stays dirty and is retried by the next flush.
    _timer ??= Timer(window, () => flush().ignore());
  }

  /// Saves any pending change now and completes once it is on disk.
  ///
  /// Waits for an in-flight save first, so saves never overlap and a change
  /// made during one is saved after it. A failing save leaves the change
  /// pending and rethrows.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    while (_running != null) {
      await _running;
    }
    if (!_dirty) return;
    _dirty = false;
    final run = _save();
    // Waiters only need "finished"; the error goes to this flush's caller.
    _running = run.then<void>((_) {}, onError: (Object _) {});
    try {
      await run;
    } on Object {
      _dirty = true;
      rethrow;
    } finally {
      _running = null;
    }
  }
}

/// Calls [flush] whenever the app leaves the resumed state (inactive,
/// hidden, paused or detached), before Android may kill the process.
///
/// Needs an initialised [WidgetsBinding]; keep the listener for the app's
/// lifetime (the binding holds it) or [AppLifecycleListener.dispose] it.
AppLifecycleListener flushOnBackground(Future<void> Function() flush) =>
    AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) flush().ignore();
      },
    );
