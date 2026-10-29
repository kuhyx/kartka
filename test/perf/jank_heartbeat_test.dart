import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/perf/jank_tracker.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

const _ms = 1000;

JankTracker _tracker({
  bool heartbeat = false,
  int Function()? monotonicMicros,
}) {
  final t = JankTracker(
    log: DiagnosticsLog(memoryPlatform().diagnostics),
    attach: false,
    heartbeat: heartbeat,
    monotonicMicros: monotonicMicros,
    clock: () => DateTime.utc(2026, 10, 29),
    refreshRate: () => 60,
  );
  addTearDown(t.dispose);
  return t;
}

void main() {
  test('vsync overhead counts toward the frame cost', () {
    // 1 ms build + 1 ms raster, but the build started 30 ms after vsync.
    final late = FrameTiming(
      vsyncStart: 0,
      buildStart: 30 * _ms,
      buildFinish: 31 * _ms,
      rasterStart: 31 * _ms,
      rasterFinish: 32 * _ms,
      rasterFinishWallTime: 32 * _ms,
    );
    final t = _tracker()
      ..screenChanged('/library')
      ..onTimings([late]);
    final s = t.summaries().single;
    expect(s.janky, 1);
    expect(s.worstMicros, 32 * _ms);
  });

  test('a late heartbeat is a stall; small and implausible ones are not', () {
    final t = _tracker()
      ..screenChanged('/library')
      ..onBeat(120 * _ms)
      ..onBeat(30 * _ms) // under the 50 ms threshold
      ..onBeat(60 * 1000 * _ms); // a minute: suspended, not frozen
    final s = t.summaries().single;
    expect(s.frames, 0); // listed although no frame arrived
    expect(s.stalls, 1);
    expect(s.worstStallMicros, 120 * _ms);
    expect(s.toLogLine(), contains('stalls=1 worstStallMs=120.0'));
  });

  test('a beat before any screen is dropped', () {
    final t = _tracker()..onBeat(500 * _ms);
    expect(t.summaries(), isEmpty);
  });

  testWidgets('the heartbeat timer measures lateness; pause stops it', (
    tester,
  ) async {
    var now = 0;
    final t = _tracker(heartbeat: true, monotonicMicros: () => now)
      ..screenChanged('/read');
    // The event loop was blocked: the 100 ms beat runs 250 ms late.
    now += 350 * _ms;
    await tester.pump(const Duration(milliseconds: 100));
    expect(t.summaries().single.stalls, 1);
    expect(t.summaries().single.worstStallMicros, 250 * _ms);
    // Backgrounded for a long time: no beat, and no stall on resume.
    void go(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);

    const inactive = AppLifecycleState.inactive;
    const hidden = AppLifecycleState.hidden;
    go([inactive, hidden, AppLifecycleState.paused]);
    now += 5000 * _ms;
    await tester.pump(const Duration(seconds: 5));
    go([hidden, inactive, AppLifecycleState.resumed]);
    now += 100 * _ms;
    await tester.pump(const Duration(milliseconds: 100));
    expect(t.summaries().single.stalls, 1);
    t.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
