import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/perf/frame_stats.dart';

const _budget = 16667;

PerfSummary _summary(String screen, List<int> ms, {int capacity = 64}) {
  final stats = ScreenFrameStats(capacity: capacity);
  for (final m in ms) {
    stats.record(m * 1000, _budget);
  }
  return stats.summary(screen, _budget);
}

void main() {
  test('nearest-rank percentiles on a known sample', () {
    final s = _summary('/library', [
      for (var i = 100; i >= 1; i--) i,
    ], capacity: 128);
    expect(s.frames, 100);
    expect(s.p50Micros, 50000);
    expect(s.p90Micros, 90000);
    expect(s.p99Micros, 99000);
    expect(s.worstMicros, 100000);
  });

  test('a frame over the budget is janky, one at the budget is not', () {
    final stats = ScreenFrameStats()
      ..record(_budget, _budget)
      ..record(_budget + 1, _budget)
      ..record(1000, _budget);
    final s = stats.summary('/browse', _budget);
    expect(s.frames, 3);
    expect(s.janky, 1);
    expect(s.jankShare, closeTo(1 / 3, 1e-9));
  });

  test('the ring keeps the newest frames; counters keep every frame', () {
    final s = _summary('/more', [90, 90, 90, 1, 2, 3, 4], capacity: 4);
    expect(s.frames, 7);
    expect(s.janky, 3);
    expect(s.worstMicros, 90000);
    // Percentiles cover only the ring: 1, 2, 3, 4 ms.
    expect(s.p50Micros, 2000);
    expect(s.p99Micros, 4000);
  });

  test('an empty screen summarises to zeros', () {
    final s = ScreenFrameStats().summary('/sources', _budget);
    expect([s.frames, s.janky, s.p50Micros, s.p99Micros], [0, 0, 0, 0]);
    expect(s.jankShare, 0);
  });

  test('dirty until marked flushed, again after new frames', () {
    final stats = ScreenFrameStats();
    expect(stats.dirty, isFalse);
    stats.record(1000, _budget);
    expect(stats.dirty, isTrue);
    stats.markFlushed(DateTime.utc(2026));
    expect(stats.dirty, isFalse);
    expect(stats.lastFlushAt, DateTime.utc(2026));
    stats.record(1000, _budget);
    expect(stats.dirty, isTrue);
  });

  test('worst first: jank share, then p99, then pattern', () {
    final calm = _summary('/a', [1, 1, 1, 1]);
    final bad = _summary('/b', [40, 1, 1, 1]);
    final badSlowTail = _summary('/c', [1, 1, 1, 50]);
    final tieA = _summary('/x', [1, 2]);
    final tieB = _summary('/w', [1, 2]);
    final sorted = [calm, tieA, bad, tieB, badSlowTail]
      ..sort(PerfSummary.worstFirst);
    expect([for (final s in sorted) s.screen], ['/c', '/b', '/w', '/x', '/a']);
  });

  test('log line names the pattern and the stats in ms', () {
    final s = _summary('/read/:sourceId', [4, 20]);
    expect(
      s.toLogLine(),
      'screen=/read/:sourceId frames=2 janky=1 worstMs=20.0 p50Ms=4.0 '
      'p90Ms=20.0 p99Ms=20.0 budgetMs=16.7 stalls=0 worstStallMs=0.0',
    );
  });
}
