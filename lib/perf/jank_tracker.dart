import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/perf/frame_stats.dart';
import 'package:kartka/platform/coalescing_saver.dart';

/// Diagnostics kind of a per-screen frame summary.
const perfJankKind = 'perf.jank';

/// Per-screen jank tracker: Flutter frame timings, attributed to the route
/// pattern on top when the engine delivers them, summarised into the shared
/// [DiagnosticsLog] as [perfJankKind] entries. Nothing is synced.
///
/// A frame's cost is vsync overhead + build + raster time (a frame whose
/// build starts late, because the UI isolate was busy, misses vsync just
/// the same); it is janky when that exceeds one refresh interval of the
/// display (16.7 ms when the rate is unknown).
///
/// Frames only report work the engine did. A UI isolate frozen by a long
/// synchronous task renders no frames at all, so a heartbeat timer fires
/// every [heartbeatInterval]; one that runs more than [stallThreshold] late
/// counts as a stall on the screen on top. The heartbeat stops while the
/// app is in the background, and lateness of [maxStall] or more (a
/// suspended process, not a frozen one) is ignored.
/// Timings arrive in engine batches (about one per second in release), so
/// frames rendered just before a navigation can land on the new screen.
///
/// A screen's summary is written when it is left, when the app leaves the
/// foreground, and while it stays on top, each at most once per
/// [flushInterval] per screen and only after new frames; a deferred flush
/// keeps its frames for the next one. Summaries carry the route pattern
/// only, never ids, URLs or titles.
class JankTracker implements ScreenObserver {
  /// A tracker writing to [log].
  ///
  /// [enabled] `false` makes every method a no-op (tests). [attach] `false`
  /// keeps it off the binding: frames come only through [onTimings].
  /// [heartbeat] (default: [attach]) runs the stall timer; tests can feed
  /// [onBeat] directly. [monotonicMicros] is the heartbeat's clock.
  new({
    required this.log,
    this.enabled = true,
    this.attach = true,
    bool? heartbeat,
    this.flushInterval = const Duration(seconds: 60),
    DateTime Function()? clock,
    double Function()? refreshRate,
    int Function()? monotonicMicros,
  }) : heartbeat = heartbeat ?? attach,
       _clock = clock ?? DateTime.now,
       _refreshRate = refreshRate ?? _viewRefreshRate,
       _monotonic = monotonicMicros ?? _stopwatchMicros;

  /// Where summaries go (the shared log in the app).
  final DiagnosticsLog log;

  final DateTime Function() _clock;
  final double Function() _refreshRate;
  final int Function() _monotonic;

  /// Gap between heartbeats.
  static const heartbeatInterval = Duration(milliseconds: 100);

  /// Lateness above this is a stall.
  static const stallThreshold = Duration(milliseconds: 50);

  /// Lateness from here on is a suspended app, not a stall.
  static const maxStall = Duration(seconds: 30);

  /// Whether the tracker does anything.
  final bool enabled;

  /// Whether the first screen hooks the binding's timings and lifecycle.
  final bool attach;

  /// Whether the first screen starts the event-loop heartbeat.
  final bool heartbeat;

  /// Shortest gap between two summaries of one screen.
  final Duration flushInterval;

  final _stats = <String, ScreenFrameStats>{};
  String? _screen;
  ScreenFrameStats? _current;
  bool _attached = false;
  AppLifecycleListener? _lifecycle;
  AppLifecycleListener? _beatLifecycle;
  Timer? _beat;
  int _lastBeat = 0;

  @override
  void screenChanged(String pattern) {
    if (!enabled) return;
    _hook();
    _startHeartbeat();
    final left = _screen;
    if (left != null) _flush(left, _current!, periodic: false);
    _screen = pattern;
    _current = _stats.putIfAbsent(
      pattern,
      () => ScreenFrameStats(startedAt: _clock()),
    );
  }

  void _hook() {
    if (!attach || _attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    _lifecycle = flushOnBackground(() async => flushAll());
  }

  void _startHeartbeat() {
    if (!heartbeat || _beatLifecycle != null) return;
    _beatLifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          state == AppLifecycleState.resumed ? _resumeBeat() : _pauseBeat(),
    );
    _resumeBeat();
  }

  void _resumeBeat() {
    if (_beat != null) return;
    _lastBeat = _monotonic();
    _beat = Timer.periodic(heartbeatInterval, (_) {
      final now = _monotonic();
      onBeat(now - _lastBeat - heartbeatInterval.inMicroseconds);
      _lastBeat = now;
    });
  }

  void _pauseBeat() {
    _beat?.cancel();
    _beat = null;
  }

  /// Records a heartbeat that ran [latenessMicros] late on the screen on
  /// top: a stall when over [stallThreshold] and under [maxStall].
  void onBeat(int latenessMicros) {
    final stats = _current;
    if (!enabled || stats == null) return;
    if (latenessMicros <= stallThreshold.inMicroseconds ||
        latenessMicros >= maxStall.inMicroseconds) {
      return;
    }
    stats.recordStall(latenessMicros);
  }

  /// Records an engine batch of [timings] against the screen on top.
  void onTimings(List<FrameTiming> timings) {
    final stats = _current;
    if (!enabled || stats == null) return;
    final budget = budgetMicros;
    for (final t in timings) {
      stats.record(
        t.vsyncOverhead.inMicroseconds +
            t.buildDuration.inMicroseconds +
            t.rasterDuration.inMicroseconds,
        budget,
      );
    }
    _flush(_screen!, stats, periodic: true);
  }

  /// One refresh interval in microseconds; 16 667 when the rate is unknown.
  int get budgetMicros {
    final rate = _refreshRate();
    return rate.isFinite && rate >= 1 ? (1e6 / rate).round() : 16667;
  }

  /// Writes every screen whose summary is due.
  void flushAll() => _stats.forEach((s, st) => _flush(s, st, periodic: false));

  void _flush(String screen, ScreenFrameStats stats, {required bool periodic}) {
    if (!stats.dirty) return;
    final now = _clock();
    final since = stats.lastFlushAt ?? (periodic ? stats.startedAt : null);
    if (since != null && now.difference(since) < flushInterval) return;
    stats.markFlushed(now);
    unawaited(
      log.append(
        DiagnosticEntry(
          at: now,
          kind: perfJankKind,
          error: stats.summary(screen, budgetMicros).toLogLine(),
        ),
      ),
    );
  }

  /// Every screen's figures, worst first.
  List<PerfSummary> summaries() {
    final budget = budgetMicros;
    return [
      for (final MapEntry(:key, :value) in _stats.entries)
        if (value.frames > 0 || value.stalls > 0) value.summary(key, budget),
    ]..sort(PerfSummary.worstFirst);
  }

  /// Forgets every in-memory figure (the diagnostics log is kept).
  void reset() {
    _stats.clear();
    final screen = _screen;
    if (screen != null) {
      _current = _stats[screen] = ScreenFrameStats(startedAt: _clock());
    }
  }

  /// Unhooks from the binding and stops the heartbeat.
  void dispose() {
    _pauseBeat();
    _beatLifecycle?.dispose();
    _beatLifecycle = null;
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    _lifecycle?.dispose();
  }

  static final _stopwatch = Stopwatch()..start();
  static int _stopwatchMicros() => _stopwatch.elapsedMicroseconds;

  static double _viewRefreshRate() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 0 : views.first.display.refreshRate;
  }
}
