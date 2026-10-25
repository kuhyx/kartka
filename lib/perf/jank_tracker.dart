import 'dart:async';
import 'dart:ui';

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
/// A frame's cost is build + raster time; it is janky when that exceeds one
/// refresh interval of the display (16.7 ms when the rate is unknown).
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
  new({
    required this.log,
    this.enabled = true,
    this.attach = true,
    this.flushInterval = const Duration(seconds: 60),
    DateTime Function()? clock,
    double Function()? refreshRate,
  }) : _clock = clock ?? DateTime.now,
       _refreshRate = refreshRate ?? _viewRefreshRate;

  /// Where summaries go (the shared log in the app).
  final DiagnosticsLog log;

  final DateTime Function() _clock;
  final double Function() _refreshRate;

  /// Whether the tracker does anything.
  final bool enabled;

  /// Whether the first screen hooks the binding's timings and lifecycle.
  final bool attach;

  /// Shortest gap between two summaries of one screen.
  final Duration flushInterval;

  final _stats = <String, ScreenFrameStats>{};
  String? _screen;
  ScreenFrameStats? _current;
  bool _attached = false;
  AppLifecycleListener? _lifecycle;

  @override
  void screenChanged(String pattern) {
    if (!enabled) return;
    _hook();
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

  /// Records an engine batch of [timings] against the screen on top.
  void onTimings(List<FrameTiming> timings) {
    final stats = _current;
    if (!enabled || stats == null) return;
    final budget = budgetMicros;
    for (final t in timings) {
      stats.record(
        t.timestampInMicroseconds(FramePhase.buildFinish) -
            t.timestampInMicroseconds(FramePhase.buildStart) +
            t.timestampInMicroseconds(FramePhase.rasterFinish) -
            t.timestampInMicroseconds(FramePhase.rasterStart),
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
        if (value.frames > 0) value.summary(key, budget),
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

  /// Unhooks from the binding.
  void dispose() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    _lifecycle?.dispose();
  }

  static double _viewRefreshRate() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 0 : views.first.display.refreshRate;
  }
}
