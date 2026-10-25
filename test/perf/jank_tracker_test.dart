import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/perf/jank_tracker.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import 'frames.dart';

typedef _Rig = ({
  JankTracker tracker,
  DiagnosticsLog log,
  void Function(int) tick,
});

_Rig _rig({double refreshRate = 60, bool enabled = true}) {
  var now = DateTime.utc(2026, 10, 25);
  final log = DiagnosticsLog(memoryPlatform().diagnostics);
  final tracker = JankTracker(
    log: log,
    enabled: enabled,
    attach: false,
    clock: () => now,
    refreshRate: () => refreshRate,
  );
  addTearDown(tracker.dispose);
  return (
    tracker: tracker,
    log: log,
    tick: (s) => now = now.add(Duration(seconds: s)),
  );
}

Future<List<String>> _lines(DiagnosticsLog log) async => [
  for (final e in await log.entries())
    if (e.kind == 'perf.jank') e.error,
];

void main() {
  test('frames go to the active screen and switch on navigation', () {
    final r = _rig();
    r.tracker
      ..onTimings([frame(5)]) // before any screen: dropped
      ..screenChanged('/library')
      ..onTimings([frame(5), frame(30)])
      ..screenChanged('/browse/source/:sourceId')
      ..onTimings([frame(2)]);
    final byScreen = {for (final s in r.tracker.summaries()) s.screen: s};
    expect(
      byScreen.keys,
      unorderedEquals(['/library', '/browse/source/:sourceId']),
    );
    expect(byScreen['/library']!.frames, 2);
    expect(byScreen['/library']!.janky, 1);
    expect(byScreen['/browse/source/:sourceId']!.frames, 1);
  });

  test('budget follows the refresh rate; a missing rate means 16.7 ms', () {
    for (final (rate, janky) in [(120.0, 1), (0.0, 0), (double.nan, 0)]) {
      final r = _rig(refreshRate: rate);
      r.tracker
        ..screenChanged('/read/:a')
        ..onTimings([frame(6, 4)]); // 10 ms: janky only at 120 Hz
      expect(r.tracker.summaries().single.janky, janky, reason: '$rate');
    }
  });

  test('leaving a screen flushes its pattern only, no ids or URLs', () async {
    final r = _rig();
    r.tracker
      ..screenChanged('/read/:sourceId/:mangaUrl/:chapterUrl')
      ..onTimings([frame(8, 12)])
      ..screenChanged('/library');
    final lines = await _lines(r.log);
    expect(lines, hasLength(1));
    expect(lines.single, startsWith('screen=/read/:sourceId/:mangaUrl/'));
    final screen = lines.single.split(' ').first.substring('screen='.length);
    for (final segment in screen.split('/')) {
      expect(segment, isNot(matches(RegExp(r'^\d+$'))));
    }
    expect(lines.single, isNot(contains('http')));
    final entry = (await r.log.entries()).single;
    expect([
      entry.sourceId,
      entry.mangaUrl,
      entry.chapterUrl,
    ], everyElement(isNull));
  });

  test('flushes are rate limited per screen and skip idle screens', () async {
    final r = _rig();
    r.tracker
      ..screenChanged('/library')
      ..onTimings([frame(5)])
      ..screenChanged('/more') // flush 1 (/library)
      ..screenChanged('/library') // /more has no frames: nothing
      ..onTimings([frame(5)])
      ..screenChanged('/more'); // /library flushed 0 s ago: deferred
    expect(await _lines(r.log), hasLength(1));
    r.tick(61);
    r.tracker.onTimings([frame(5)]); // /more due: periodic flush
    r.tracker.flushAll(); // /library's deferred frames now due
    final lines = await _lines(r.log);
    expect(lines, hasLength(3));
    expect(lines.last, startsWith('screen=/library frames=2 '));
    r.tracker.flushAll(); // nothing new
    expect(await _lines(r.log), hasLength(3));
  });

  test('disabled: ignores everything', () async {
    final r = _rig(enabled: false);
    r.tracker
      ..screenChanged('/library')
      ..onTimings([frame(50)])
      ..screenChanged('/more');
    expect(r.tracker.summaries(), isEmpty);
    expect(await _lines(r.log), isEmpty);
  });

  test('reset clears stats, keeps tracking the current screen', () {
    final r = _rig();
    r.tracker
      ..screenChanged('/library')
      ..onTimings([frame(5)])
      ..screenChanged('/more')
      ..onTimings([frame(5)])
      ..reset()
      ..onTimings([frame(40)]);
    final s = r.tracker.summaries().single;
    expect((s.screen, s.frames, s.janky), ('/more', 1, 1));
  });

  testWidgets('attaches to the binding: real timings and pause flush', (
    tester,
  ) async {
    final log = DiagnosticsLog(memoryPlatform().diagnostics);
    final tracker = JankTracker(log: log)..screenChanged('/library');
    addTearDown(tracker.dispose);
    tester.binding.platformDispatcher.onReportTimings!([frame(30)]);
    expect(tracker.summaries().single.frames, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() async {
      expect(await _lines(log), [startsWith('screen=/library frames=1 ')]);
    });
    tracker.dispose();
    tester.binding.platformDispatcher.onReportTimings?.call([frame(30)]);
    expect(tracker.summaries().single.frames, 1);
  });

  testWidgets('default refresh rate comes from the first view', (tester) async {
    tester.view.display.refreshRate = 120;
    addTearDown(tester.view.display.resetRefreshRate);
    final tracker = JankTracker(
      log: DiagnosticsLog(memoryPlatform().diagnostics),
      attach: false,
    )..screenChanged('/library');
    addTearDown(tracker.dispose);
    tracker.onTimings([frame(10)]);
    expect(tracker.summaries().single.janky, 1);
    expect(tracker.summaries().single.budgetMicros, 8333);
  });
}
