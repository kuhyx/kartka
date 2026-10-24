/// Sorting, filtering and freshness for the Sources ranking.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/thresholds.dart';

/// A column the ranking can be sorted by. Each sorts best-first by default.
enum HealthSort {
  /// Evaluator rank (1 = best).
  rank('Rank', higherIsBetter: false),

  /// Weighted score.
  score('Score', higherIsBetter: true),

  /// Display name, A to Z.
  name('Name', higherIsBetter: false),

  /// Uptime ratio.
  uptime('Uptime', higherIsBetter: true),

  /// Median latency.
  latencyP50('Latency p50', higherIsBetter: false),

  /// 95th-percentile latency.
  latencyP95('Latency p95', higherIsBetter: false),

  /// Challenge rate.
  blocking('Blocking rate', higherIsBetter: false),

  /// Coverage ratio.
  coverage('Coverage', higherIsBetter: true),

  /// Chapter completeness.
  completeness('Chapter completeness', higherIsBetter: true),

  /// Median page width.
  imageWidth('Image width', higherIsBetter: true),

  /// Median JPEG quality.
  jpegQuality('JPEG quality', higherIsBetter: true);

  const HealthSort(this.label, {required this.higherIsBetter});

  /// Menu label.
  final String label;

  /// Whether larger values are better (so sort descending by default).
  final bool higherIsBetter;

  /// The sort key of [r]; null when the metric is missing.
  Comparable<Object>? keyOf(SourceHealthRecord r) => switch (this) {
    rank => r.rank,
    score => r.score,
    name => r.name.toLowerCase(),
    uptime => r.uptime?.ratio,
    latencyP50 => r.latency?.p50,
    latencyP95 => r.latency?.p95,
    blocking => r.blocking?.challengeRate,
    coverage => r.coverage?.ratio,
    completeness => r.completeness?.medianRatio,
    imageWidth => r.imageQuality?.medianWidthPx,
    jpegQuality => r.imageQuality?.medianJpegQuality,
  };
}

/// What the ranking shows: one sort plus verdict/lang/origin filters.
@immutable
class HealthQuery {
  /// Creates a query; empty [verdicts] and null [lang]/[origin] mean "all".
  const HealthQuery({
    this.sort = HealthSort.rank,
    this.reversed = false,
    this.verdicts = const {},
    this.lang,
    this.origin,
  });

  /// Sort column.
  final HealthSort sort;

  /// Worst-first instead of best-first. Missing values stay last.
  final bool reversed;

  /// Verdicts to show; empty shows all.
  final Set<HealthVerdict> verdicts;

  /// Language to show; null shows all.
  final String? lang;

  /// Origin to show; null shows all.
  final String? origin;

  /// A copy with the given fields replaced.
  HealthQuery copyWith({
    HealthSort? sort,
    bool? reversed,
    Set<HealthVerdict>? verdicts,
    String? lang,
    String? origin,
    bool clearLang = false,
    bool clearOrigin = false,
  }) => HealthQuery(
    sort: sort ?? this.sort,
    reversed: reversed ?? this.reversed,
    verdicts: verdicts ?? this.verdicts,
    lang: clearLang ? null : lang ?? this.lang,
    origin: clearOrigin ? null : origin ?? this.origin,
  );

  /// [records] filtered and sorted; ties break by name, then id.
  List<SourceHealthRecord> apply(List<SourceHealthRecord> records) {
    final shown = records.where(_matches).toList()..sort(_compare);
    return shown;
  }

  bool _matches(SourceHealthRecord r) =>
      (verdicts.isEmpty || verdicts.contains(r.verdict)) &&
      (lang == null || r.lang == lang) &&
      (origin == null || r.origin == origin);

  int _compare(SourceHealthRecord a, SourceHealthRecord b) {
    final ka = sort.keyOf(a);
    final kb = sort.keyOf(b);
    if (ka == null || kb == null) {
      if (ka != kb) return ka == null ? 1 : -1;
    } else {
      final ascending = ka.compareTo(kb);
      final bestFirst = sort.higherIsBetter ? -ascending : ascending;
      final c = reversed ? -bestFirst : bestFirst;
      if (c != 0) return c;
    }
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }
}

/// Distinct non-empty languages in [records], sorted.
List<String> langsOf(List<SourceHealthRecord> records) =>
    _distinct(records.map((r) => r.lang));

/// Distinct non-empty origins in [records], sorted.
List<String> originsOf(List<SourceHealthRecord> records) =>
    _distinct(records.map((r) => r.origin));

List<String> _distinct(Iterable<String> values) =>
    values.where((v) => v.isNotEmpty).toSet().toList()..sort();

/// The newest `probedAt` in [records]; null when none has one.
DateTime? lastEvaluated(List<SourceHealthRecord> records) {
  DateTime? newest;
  for (final r in records) {
    final at = r.probedAt;
    if (at != null && (newest == null || at.isAfter(newest))) newest = at;
  }
  return newest;
}

/// Whether results from [at] are too old to trust at [now]. Never evaluated
/// counts as stale.
bool isStale(DateTime? at, DateTime now) =>
    at == null || now.difference(at) > HealthThresholds.staleAfter;
