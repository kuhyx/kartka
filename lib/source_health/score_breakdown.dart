/// The §5 score split into its five weighted parts.
library;

import 'dart:math' as math;

import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/thresholds.dart';

/// One weighted part of the score.
class ScorePart {
  /// Creates a part.
  const ScorePart(this.label, this.weight, this.normalized);

  /// Metric name.
  final String label;

  /// Share of the total score (§5 weight).
  final double weight;

  /// The metric mapped onto 0..1; null when not measured.
  final double? normalized;

  /// weight × normalized; null when not measured.
  double? get points => normalized == null ? null : weight * normalized!;
}

/// The five parts of [r]'s score, in §5 order.
List<ScorePart> scoreBreakdown(SourceHealthRecord r) {
  final width = r.imageQuality?.medianWidthPx;
  final p95 = r.latency?.p95;
  return [
    ScorePart('Coverage', HealthThresholds.weightCoverage, r.coverage?.ratio),
    ScorePart(
      'Chapter completeness',
      HealthThresholds.weightCompleteness,
      r.completeness?.medianRatio,
    ),
    ScorePart('Uptime', HealthThresholds.weightUptime, r.uptime?.ratio),
    ScorePart(
      'Image quality',
      HealthThresholds.weightImageQuality,
      width == null ? null : math.min(1, width / HealthThresholds.fullWidthPx),
    ),
    ScorePart(
      'Latency',
      HealthThresholds.weightLatency,
      p95 == null ? null : math.max(0, 1 - p95 / HealthThresholds.worstP95Ms),
    ),
  ];
}
