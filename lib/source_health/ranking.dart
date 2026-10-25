/// Sorting, filtering and freshness for the Sources ranking.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/fuzzy_match.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/search_text.dart';
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

  new(this.label, {required this.higherIsBetter});

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

/// What the ranking shows: one sort, a fuzzy search and verdict / lang /
/// origin / reason / minimum-score filters, all ANDed together.
@immutable
class HealthQuery {
  /// Creates a query; empty [verdicts]/[reasons]/[search], null
  /// [lang]/[origin] and a zero [minScore] mean "all".
  const new({
    this.sort = HealthSort.rank,
    this.reversed = false,
    this.verdicts = const {},
    this.lang,
    this.origin,
    this.search = '',
    this.reasons = const {},
    this.minScore = 0,
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

  /// Fuzzy search text; blank shows all. Matches rank by quality first.
  final String search;

  /// Reasons to show (any of them); empty shows all.
  final Set<HealthReason> reasons;

  /// Lowest evaluator score shown; above 0 an unscored source is hidden.
  final double minScore;

  /// A copy with the given fields replaced.
  HealthQuery copyWith({
    HealthSort? sort,
    bool? reversed,
    Set<HealthVerdict>? verdicts,
    String? lang,
    String? origin,
    String? search,
    Set<HealthReason>? reasons,
    double? minScore,
    bool clearLang = false,
    bool clearOrigin = false,
  }) => HealthQuery(
    sort: sort ?? this.sort,
    reversed: reversed ?? this.reversed,
    verdicts: verdicts ?? this.verdicts,
    lang: clearLang ? null : lang ?? this.lang,
    origin: clearOrigin ? null : origin ?? this.origin,
    search: search ?? this.search,
    reasons: reasons ?? this.reasons,
    minScore: minScore ?? this.minScore,
  );

  /// [records] filtered and sorted. With a search, better matches come
  /// first and the sort only breaks ties; then name, then id. One
  /// comparator, because Dart's sort is not stable.
  List<SourceHealthRecord> apply(List<SourceHealthRecord> records) {
    final query = FuzzyQuery(search);
    final names = {for (final r in records) r.id: r.name};
    final scored = <(SourceHealthRecord, double)>[];
    for (final r in records.where(_matches)) {
      final text = query.isEmpty
          ? null
          : searchTextOf(r, nameOf: (id) => names[id]);
      final s = text == null ? 1.0 : query.score(text.primary, text.secondary);
      if (s != null) scored.add((r, s));
    }
    scored.sort((a, b) {
      final byMatch = b.$2.compareTo(a.$2);
      return byMatch != 0 ? byMatch : _compare(a.$1, b.$1);
    });
    return [for (final (r, _) in scored) r];
  }

  bool _matches(SourceHealthRecord r) =>
      (verdicts.isEmpty || verdicts.contains(r.verdict)) &&
      (lang == null || r.lang == lang) &&
      (origin == null || r.origin == origin) &&
      (reasons.isEmpty || reasonsOf(r).any(reasons.contains)) &&
      (minScore <= 0 || (r.score ?? -1) >= minScore - _scoreSlack);

  // Slider steps are sums of 0.05, so 0.85 can arrive as 0.8500000000000001.
  static const double _scoreSlack = 1e-9;

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
