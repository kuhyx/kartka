import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/perf/jank_tracker.dart';
import 'package:kartka/perf/performance_screen.dart';

/// Route of the Performance screen (opened from the More tab).
const performanceRoute = '/performance';

/// The perf part: the per-screen jank tracker on the shared diagnostics log.
KartkaFeature perfFeature(KartkaEnv env) => buildPerfFeature(
  JankTracker(log: DiagnosticsLog.of(env.platform.diagnostics)),
);

/// The perf feature around [tracker] (tests pass a detached one).
KartkaFeature buildPerfFeature(JankTracker tracker) => KartkaFeature(
  id: 'perf',
  routes: [
    GoRoute(
      path: performanceRoute,
      builder: (_, _) => PerformanceScreen(tracker: tracker),
    ),
  ],
  settingsTiles: [
    (context) => ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('Performance'),
      subtitle: const Text('Slow frames per screen'),
      onTap: () => unawaited(context.push(performanceRoute)),
    ),
  ],
  services: [tracker],
);
