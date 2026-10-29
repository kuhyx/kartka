import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/perf/jank_tracker.dart';
import 'package:kartka/perf/perf_feature.dart';
import 'package:kartka/perf/performance_screen.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import 'frames.dart';

JankTracker _tracker() {
  final t = JankTracker(
    log: DiagnosticsLog(memoryPlatform().diagnostics),
    attach: false,
    refreshRate: () => 60,
  );
  addTearDown(t.dispose);
  return t;
}

void main() {
  testWidgets('lists screens worst first; Reset clears the stats', (
    tester,
  ) async {
    final tracker = _tracker()
      ..screenChanged('/library')
      ..onTimings([frame(2), frame(3)])
      ..screenChanged('/read/:sourceId/:mangaUrl/:chapterUrl')
      ..onTimings([frame(40), frame(3)]);
    await tester.pumpWidget(
      MaterialApp(home: PerformanceScreen(tracker: tracker)),
    );
    final reader = tester.getTopLeft(find.textContaining('/read/'));
    final library = tester.getTopLeft(find.text('/library'));
    expect(reader.dy, lessThan(library.dy));
    expect(find.textContaining('1 of 2 frames janky (50 %)'), findsOneWidget);
    expect(find.textContaining('worst 40.0 ms'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('/library'), findsNothing);
    expect(find.text('No frames measured yet'), findsOneWidget);
  });

  testWidgets('event-loop stalls show on their screen', (tester) async {
    final tracker = _tracker()
      ..screenChanged('/library')
      ..onBeat(180000)
      ..screenChanged('/browse')
      ..onBeat(60000)
      ..onBeat(90000);
    await tester.pumpWidget(
      MaterialApp(home: PerformanceScreen(tracker: tracker)),
    );
    expect(find.textContaining('1 stall (worst 180.0 ms)'), findsOneWidget);
    expect(find.textContaining('2 stalls (worst 90.0 ms)'), findsOneWidget);
  });

  testWidgets('More tile opens the screen; the tracker sees the route', (
    tester,
  ) async {
    final platform = memoryPlatform();
    final tracker = _tracker();
    final registry = KartkaRegistry.build(platform, [
      (_) => buildPerfFeature(tracker),
    ]);
    await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(find.byType(PerformanceScreen), findsOneWidget);
    tracker.onTimings([frame(1)]);
    expect(tracker.summaries().single.screen, performanceRoute);
  });

  test(
    'the registered factory builds a live tracker on the diagnostics log',
    () {
      final feature = perfFeature(KartkaEnv(memoryPlatform()));
      final tracker = feature.services.single as JankTracker;
      addTearDown(tracker.dispose);
      expect(tracker.enabled, isTrue);
      expect(feature.routes, hasLength(1));
    },
  );
}
