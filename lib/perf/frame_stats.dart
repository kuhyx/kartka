import 'dart:typed_data';

/// Frame-time counters for one screen, plus a fixed ring of the newest frame
/// durations for percentiles.
///
/// [record] is the per-frame path: it writes into preallocated typed lists
/// and allocates nothing. Sorting happens only in [summary].
class ScreenFrameStats {
  /// Stats keeping the newest [capacity] frame times, started at [startedAt].
  new({this.capacity = defaultCapacity, this.startedAt})
    : _ring = Int32List(capacity),
      _scratch = Int32List(capacity);

  /// Frames kept for percentiles by default (about 8 s at 60 Hz).
  static const defaultCapacity = 512;

  /// Size of the percentile ring.
  final int capacity;

  /// When the screen was first seen; the periodic flush counts from here.
  final DateTime? startedAt;

  final Int32List _ring;
  final Int32List _scratch;
  int _next = 0;
  int _filled = 0;
  int _flushedFrames = 0;
  int _flushedStalls = 0;

  /// Every frame recorded.
  int frames = 0;

  /// Frames slower than their budget.
  int janky = 0;

  /// The slowest frame, in microseconds.
  int worstMicros = 0;

  /// Event-loop stalls: heartbeats that ran late by more than the threshold.
  int stalls = 0;

  /// The longest stall, in microseconds.
  int worstStallMicros = 0;

  /// When a summary of this screen was last written to the log.
  DateTime? lastFlushAt;

  /// Counts one frame that took [micros] against a [budgetMicros] budget.
  void record(int micros, int budgetMicros) {
    frames++;
    if (micros > budgetMicros) janky++;
    if (micros > worstMicros) worstMicros = micros;
    _ring[_next] = micros;
    _next = (_next + 1) % capacity;
    if (_filled < capacity) _filled++;
  }

  /// Counts one event-loop stall of [micros].
  void recordStall(int micros) {
    stalls++;
    if (micros > worstStallMicros) worstStallMicros = micros;
  }

  /// Whether frames or stalls arrived since the last [markFlushed].
  bool get dirty => frames != _flushedFrames || stalls != _flushedStalls;

  /// Notes that a summary was written at [at].
  void markFlushed(DateTime at) {
    lastFlushAt = at;
    _flushedFrames = frames;
    _flushedStalls = stalls;
  }

  /// The current figures for [screen] against [budgetMicros].
  PerfSummary summary(String screen, int budgetMicros) {
    final sorted = Int32List.sublistView(_scratch, 0, _filled)
      ..setRange(0, _filled, _ring)
      ..sort();
    int pct(int p) =>
        _filled == 0 ? 0 : sorted[((p * _filled + 99) ~/ 100) - 1];
    return PerfSummary(
      screen: screen,
      frames: frames,
      janky: janky,
      worstMicros: worstMicros,
      p50Micros: pct(50),
      p90Micros: pct(90),
      p99Micros: pct(99),
      budgetMicros: budgetMicros,
      stalls: stalls,
      worstStallMicros: worstStallMicros,
    );
  }
}

/// One screen's figures, as shown on the Performance screen and logged as
/// `perf.jank`. Times are microseconds; percentiles are nearest-rank over
/// the screen's newest frames.
class PerfSummary {
  /// Creates a summary.
  const new({
    required this.screen,
    required this.frames,
    required this.janky,
    required this.worstMicros,
    required this.p50Micros,
    required this.p90Micros,
    required this.p99Micros,
    required this.budgetMicros,
    this.stalls = 0,
    this.worstStallMicros = 0,
  });

  /// The screen's route pattern.
  final String screen;

  /// Frames measured.
  final int frames;

  /// Frames over [budgetMicros].
  final int janky;

  /// Slowest frame.
  final int worstMicros;

  /// Median frame time.
  final int p50Micros;

  /// 90th percentile frame time.
  final int p90Micros;

  /// 99th percentile frame time.
  final int p99Micros;

  /// The frame budget (one refresh interval).
  final int budgetMicros;

  /// Event-loop stalls (UI isolate frozen, seen by the heartbeat).
  final int stalls;

  /// Longest stall.
  final int worstStallMicros;

  /// Share of janky frames, 0 when nothing was measured.
  double get jankShare => frames == 0 ? 0 : janky / frames;

  /// Sort order putting the worst screen first: higher jank share, then
  /// higher p99, then pattern.
  static int worstFirst(PerfSummary a, PerfSummary b) {
    final share = b.jankShare.compareTo(a.jankShare);
    if (share != 0) return share;
    final tail = b.p99Micros.compareTo(a.p99Micros);
    return tail != 0 ? tail : a.screen.compareTo(b.screen);
  }

  /// The diagnostics line: pattern plus stats, times in milliseconds.
  String toLogLine() =>
      'screen=$screen frames=$frames janky=$janky '
      'worstMs=${ms(worstMicros)} p50Ms=${ms(p50Micros)} '
      'p90Ms=${ms(p90Micros)} p99Ms=${ms(p99Micros)} '
      'budgetMs=${ms(budgetMicros)} '
      'stalls=$stalls worstStallMs=${ms(worstStallMicros)}';

  /// [micros] as milliseconds with one decimal.
  static String ms(int micros) => (micros / 1000).toStringAsFixed(1);
}
