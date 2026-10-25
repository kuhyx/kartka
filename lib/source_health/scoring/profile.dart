/// The scoring profile (contract §5): user-tunable weights, keep bar and cut
/// switches, shared by the app and the Python evaluator.
///
/// [defaultScoringProfile] is the evaluator's historic scoring. It is
/// immutable, always available, and what "Reset to evaluator defaults"
/// restores. The Python side defines the same numbers in `profile.py`;
/// `tools/source_eval/tests/fixtures/scoring_profile.json` pins both.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/source_health/model/json_read.dart';
import 'package:kartka/source_health/reason_filter.dart';

/// The DEFAULT keep bar: a source scoring at least this is kept.
const double kDefaultKeepScore = 0.90;

/// Weights of the four score parts, each 0..1 (0 turns a part off). Only
/// their ratios matter: scoring uses [normalised].
@immutable
class ScoreWeights {
  /// The DEFAULT weights unless overridden.
  const new({
    this.completeCoverage = 0.50,
    this.uptime = 0.20,
    this.imageQuality = 0.15,
    this.speed = 0.15,
  });

  /// Builds weights from [values] in [keys] order.
  new fromValues(List<double> values)
    : this(
        completeCoverage: values[0],
        uptime: values[1],
        imageQuality: values[2],
        speed: values[3],
      );

  /// Wire names, in score order.
  static const List<String> keys = [
    'completeCoverage',
    'uptime',
    'imageQuality',
    'speed',
  ];

  /// Share of the merged coverage: found with a complete chapter list (the
  /// former coverage .30 + chapter completeness .20).
  final double completeCoverage;

  /// Share of the uptime ratio.
  final double uptime;

  /// Share of the image quality.
  final double imageQuality;

  /// Share of the speed (the former latency part).
  final double speed;

  /// The four weights in [keys] order.
  List<double> get values => [completeCoverage, uptime, imageQuality, speed];

  /// Sum of the raw weights, added in order (as the evaluator does).
  double get total => values.fold(0, (a, b) => a + b);

  /// These weights scaled to sum 1. Needs a non-zero [total].
  ScoreWeights get normalised {
    final t = total;
    return ScoreWeights.fromValues([for (final v in values) v / t]);
  }

  /// A copy with the weight at [index] (a [keys] position) set to [value].
  ScoreWeights withValue(int index, double value) =>
      ScoreWeights.fromValues([...values]..[index] = value);

  @override
  bool operator ==(Object other) =>
      other is ScoreWeights && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

/// Pre-2026-10-25 weights and their old defaults; they sum to the merged one.
const Map<String, double> _legacyWeights = {
  'coverage': 0.30,
  'chapterCompleteness': 0.20,
};

/// Wire names of the cut switches, by reason. A subset is a graded score
/// penalty, not a switch (the old `cuts.subset` is ignored).
const Map<HealthReason, String> kCutWireNames = {
  HealthReason.blocking: 'blocking',
  HealthReason.coverage: 'coverage',
  HealthReason.uptime: 'uptime',
  HealthReason.browserEngine: 'needsBrowserEngine',
  HealthReason.pagesNeverLoad: 'pagesNeverLoad',
};

/// Weights, pages-load multiplier, keep bar and cut switches.
@immutable
class ScoringProfile {
  /// The DEFAULT profile unless overridden: no cut switch is on, so the
  /// score alone decides.
  const new({
    this.weights = const ScoreWeights(),
    this.pagesLoadMultiplier = true,
    this.keepScore = kDefaultKeepScore,
    this.cuts = const {},
  });

  /// Parses the wire form; null when invalid (callers fall back to DEFAULT).
  ///
  /// A missing field takes its DEFAULT and unknown keys are ignored. A field
  /// of the wrong type, a weight or `keepScore` outside 0..1 and all-zero
  /// weights make the whole profile invalid.
  static ScoringProfile? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    final weights = _weights(m['weights']);
    final cuts = _cuts(m['cuts']);
    final multiplier = m['pagesLoadMultiplier'] ?? true;
    final keep = _unit(m['keepScore'] ?? kDefaultKeepScore);
    if (weights == null ||
        cuts == null ||
        multiplier is! bool ||
        keep == null ||
        weights.total <= 0) {
      return null;
    }
    return ScoringProfile(
      weights: weights,
      pagesLoadMultiplier: multiplier,
      keepScore: keep,
      cuts: cuts,
    );
  }

  /// Per-part weights.
  final ScoreWeights weights;

  /// Whether `pagesLoad.ratio` multiplies the score.
  final bool pagesLoadMultiplier;

  /// A source scoring at least this is kept.
  final double keepScore;

  /// Reasons that cut a source they apply to, whatever its score.
  final Set<HealthReason> cuts;

  /// Equal to [defaultScoringProfile] by value.
  bool get isDefault => this == defaultScoringProfile;

  /// `default` when [isDefault], else `custom` (the meta node's `name`).
  String get name => isDefault ? 'default' : 'custom';

  /// A copy with the given fields replaced.
  ScoringProfile copyWith({
    ScoreWeights? weights,
    bool? pagesLoadMultiplier,
    double? keepScore,
    Set<HealthReason>? cuts,
  }) => ScoringProfile(
    weights: weights ?? this.weights,
    pagesLoadMultiplier: pagesLoadMultiplier ?? this.pagesLoadMultiplier,
    keepScore: keepScore ?? this.keepScore,
    cuts: cuts ?? this.cuts,
  );

  /// The wire form (no `name`; the meta node adds it).
  Map<String, Object?> toJson() => {
    'weights': {
      for (final (i, key) in ScoreWeights.keys.indexed) key: weights.values[i],
    },
    'pagesLoadMultiplier': pagesLoadMultiplier,
    'keepScore': keepScore,
    'cuts': {
      for (final e in kCutWireNames.entries) e.value: cuts.contains(e.key),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is ScoringProfile &&
      other.weights == weights &&
      other.pagesLoadMultiplier == pagesLoadMultiplier &&
      other.keepScore == keepScore &&
      setEquals(other.cuts, cuts);

  @override
  int get hashCode => Object.hash(
    weights,
    pagesLoadMultiplier,
    keepScore,
    Object.hashAllUnordered(cuts),
  );
}

/// The evaluator's historic scoring. Never mutated.
const ScoringProfile defaultScoringProfile = ScoringProfile();

/// A finite number in 0..1, else null.
double? _unit(Object? v) =>
    v is num && v.isFinite && v >= 0 && v <= 1 ? v.toDouble() : null;

/// Without `completeCoverage`, the legacy `coverage` and
/// `chapterCompleteness` (each defaulting to its old value) add up to it; a
/// sum above 1 scales every weight down by it, keeping their ratios.
ScoreWeights? _weights(Object? raw) {
  if (raw == null) return const ScoreWeights();
  final m = asMap(raw);
  if (m == null) return null;
  final values = <double>[];
  for (final (i, key) in ScoreWeights.keys.indexed) {
    final v = m.containsKey(key)
        ? _unit(m[key])
        : const ScoreWeights().values[i];
    if (v == null) return null;
    values.add(v);
  }
  if (m.containsKey(ScoreWeights.keys.first)) {
    return ScoreWeights.fromValues(values);
  }
  var merged = 0.0;
  for (final MapEntry(:key, value: old) in _legacyWeights.entries) {
    final v = _unit(m.containsKey(key) ? m[key] : old);
    if (v == null) return null;
    merged += v;
  }
  values[0] = merged;
  final scale = merged > 1 ? merged : 1.0;
  return ScoreWeights.fromValues([for (final v in values) v / scale]);
}

Set<HealthReason>? _cuts(Object? raw) {
  if (raw == null) return const {};
  final m = asMap(raw);
  if (m == null) return null;
  final on = <HealthReason>{};
  for (final MapEntry(key: reason, value: wire) in kCutWireNames.entries) {
    final v = m[wire];
    if (v != null && v is! bool) return null;
    if (v == true) on.add(reason);
  }
  return on;
}

/// Rounds [x] to 3 places from its exact binary value, halves up, exactly
/// as the evaluator's `round3` (Decimal ROUND_HALF_UP) does before comparing
/// to the keep bar, so near-ties land the same way on both sides.
double round3(double x) => double.parse(x.toStringAsFixed(3));
