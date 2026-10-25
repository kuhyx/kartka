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

/// Weights of the five score parts, each 0..1 (0 turns a part off). Only
/// their ratios matter: scoring uses [normalised].
@immutable
class ScoreWeights {
  /// The DEFAULT weights unless overridden.
  const new({
    this.coverage = 0.30,
    this.chapterCompleteness = 0.20,
    this.uptime = 0.20,
    this.imageQuality = 0.15,
    this.speed = 0.15,
  });

  /// Builds weights from [values] in [keys] order.
  new fromValues(List<double> values)
    : this(
        coverage: values[0],
        chapterCompleteness: values[1],
        uptime: values[2],
        imageQuality: values[3],
        speed: values[4],
      );

  /// Wire names, in score order.
  static const List<String> keys = [
    'coverage',
    'chapterCompleteness',
    'uptime',
    'imageQuality',
    'speed',
  ];

  /// Share of the coverage ratio.
  final double coverage;

  /// Share of the chapter completeness.
  final double chapterCompleteness;

  /// Share of the uptime ratio.
  final double uptime;

  /// Share of the image quality.
  final double imageQuality;

  /// Share of the speed (the former latency part).
  final double speed;

  /// The five weights in [keys] order.
  List<double> get values => [
    coverage,
    chapterCompleteness,
    uptime,
    imageQuality,
    speed,
  ];

  /// Sum of the raw weights.
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

/// Wire names of the cut switches, by reason.
const Map<HealthReason, String> kCutWireNames = {
  HealthReason.blocking: 'blocking',
  HealthReason.subset: 'subset',
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
  return ScoreWeights.fromValues(values);
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

/// Rounds [x] to 3 places, as the evaluator does before comparing to the
/// keep bar.
double round3(double x) => (x * 1000).round() / 1000;
