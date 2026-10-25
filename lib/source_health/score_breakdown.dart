/// The §5 score split into its five weighted parts and the pages-load
/// multiplier: score = (sum of parts) × pagesLoad.ratio, under a
/// [ScoringProfile] (the DEFAULT one unless given).
library;

import 'dart:math' as math;

import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/thresholds.dart';

/// One weighted part of the score.
class ScorePart {
  /// Creates a part.
  const new(this.label, this.weight, this.normalized);

  /// Metric name.
  final String label;

  /// Share of the total score (the profile's normalised weight).
  final double weight;

  /// The metric mapped onto 0..1; null when not measured.
  final double? normalized;

  /// weight × normalized; null when not measured.
  double? get points => normalized == null ? null : weight * normalized!;
}

/// The pages-load multiplier of [r]'s score; null when the run predates
/// `pagesLoad` or its ratio was not measured (then it is not applied).
double? pagesLoadFactor(SourceHealthRecord r) => r.pagesLoad?.ratio;

/// [r]'s score recomputed from its metrics under [profile]: the weighted
/// sum, times the pages-load multiplier when the profile applies it and the
/// record has one. Not rounded.
double recomputedScore(
  SourceHealthRecord r, [
  ScoringProfile profile = defaultScoringProfile,
]) =>
    scoreBreakdown(r, profile).fold<double>(0, (s, p) => s + (p.points ?? 0)) *
    (profile.pagesLoadMultiplier ? pagesLoadFactor(r) ?? 1 : 1);

/// The five parts of [r]'s score under [profile], in §5 order.
List<ScorePart> scoreBreakdown(
  SourceHealthRecord r, [
  ScoringProfile profile = defaultScoringProfile,
]) {
  final width = r.imageQuality?.medianWidthPx;
  final p95 = r.latency?.p95;
  final w = profile.weights.normalised;
  return [
    ScorePart('Coverage', w.coverage, r.coverage?.ratio),
    ScorePart(
      'Chapter completeness',
      w.chapterCompleteness,
      r.completeness?.medianRatio,
    ),
    ScorePart('Uptime', w.uptime, r.uptime?.ratio),
    ScorePart(
      'Image quality',
      w.imageQuality,
      width == null ? null : math.min(1, width / HealthThresholds.fullWidthPx),
    ),
    ScorePart(
      'Latency',
      w.speed,
      p95 == null ? null : math.max(0, 1 - p95 / HealthThresholds.worstP95Ms),
    ),
  ];
}
