/// The §5 score split into its four weighted parts and two multipliers:
/// score = (sum of parts) × pagesLoad.ratio × subset factor, under a
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

/// The graded subset penalty of [r]: 1 − 0.5 × the published `subsetOf`
/// overlap; null when [r] is no subset (or its overlap is unknown). The
/// evaluator decides `subsetOf` (it needs every source's found titles).
double? subsetFactor(SourceHealthRecord r) {
  final overlap = r.subsetOf?.overlap;
  return overlap == null ? null : 1 - HealthThresholds.subsetPenalty * overlap;
}

/// The merged coverage part of [r]: `coverage.completeRatio`; on a run
/// before it, the old coverage and completeness in their old proportion
/// (an unmeasured one counts 0); null when neither was measured.
double? coveragePart(SourceHealthRecord r) {
  final complete = r.coverage?.completeRatio;
  if (complete != null) return complete;
  final coverage = r.coverage?.ratio;
  final chapters = r.completeness?.medianRatio;
  if (coverage == null && chapters == null) return null;
  const share = HealthThresholds.legacyCoverageShare;
  return share * (coverage ?? 0) + (1 - share) * (chapters ?? 0);
}

/// [r]'s score recomputed from its metrics under [profile], in the
/// evaluator's order: the weighted sum, times the pages-load multiplier when
/// the profile applies it and the record has one, times [subsetFactor].
/// Not rounded.
double recomputedScore(
  SourceHealthRecord r, [
  ScoringProfile profile = defaultScoringProfile,
]) {
  var total = 0.0;
  for (final p in scoreBreakdown(r, profile)) {
    total += p.points ?? 0;
  }
  final pages = profile.pagesLoadMultiplier ? pagesLoadFactor(r) : null;
  return (pages == null ? total : total * pages) * (subsetFactor(r) ?? 1);
}

/// The four parts of [r]'s score under [profile], in §5 order.
List<ScorePart> scoreBreakdown(
  SourceHealthRecord r, [
  ScoringProfile profile = defaultScoringProfile,
]) {
  final width = r.imageQuality?.medianWidthPx;
  final p95 = r.latency?.p95;
  final w = profile.weights.normalised;
  return [
    ScorePart('Coverage', w.completeCoverage, coveragePart(r)),
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
