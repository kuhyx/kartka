/// The §5 source-health record (evaluator → RTDB → app UI).
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/json_read.dart';
import 'package:kartka/source_health/model/metrics.dart';

/// The §5 `flags` entry for a source whose extension needs a browser engine.
const needsBrowserEngineFlag = 'needs-browser-engine';

/// One source's evaluation. Only [id] is required; every metric block is
/// null until the evaluator has measured it.
@immutable
class SourceHealthRecord {
  /// Creates a record.
  const new({
    required this.id,
    required this.name,
    this.lang = '',
    this.origin = '',
    this.probedAt,
    this.uptime,
    this.latency,
    this.blocking,
    this.coverage,
    this.completeness,
    this.imageQuality,
    this.subsetOf,
    this.availability,
    this.score,
    this.rank,
    this.verdict = HealthVerdict.pending,
    this.cutReasons = const [],
    this.flags = const [],
  });

  /// Parses a §5 record; null unless [json] is a map with a string `id`.
  static SourceHealthRecord? fromJson(Object? json) {
    final m = asMap(json);
    final id = m == null ? null : readString(m, 'id');
    if (id == null) return null;
    final j = m!;
    return SourceHealthRecord(
      id: id,
      name: readString(j, 'name') ?? id,
      lang: readString(j, 'lang') ?? '',
      origin: readString(j, 'origin') ?? '',
      probedAt: readInstant(j, 'probedAt'),
      uptime: UptimeMetric.fromJson(j['uptime']),
      latency: LatencyMetric.fromJson(j['latencyMs']),
      blocking: BlockingMetric.fromJson(j['blocking']),
      coverage: CoverageMetric.fromJson(j['coverage']),
      completeness: CompletenessMetric.fromJson(j['chapterCompleteness']),
      imageQuality: ImageQualityMetric.fromJson(j['imageQuality']),
      subsetOf: SubsetOfMetric.fromJson(j['subsetOf']),
      availability: AvailabilityMetric.fromJson(j['availability']),
      score: readDouble(j, 'score'),
      rank: readInt(j, 'rank'),
      verdict: HealthVerdict.parse(readString(j, 'verdict')),
      cutReasons: readStrings(j, 'cutReasons'),
      flags: readStrings(j, 'flags'),
    );
  }

  /// Source id (`SourceRef.id`).
  final String id;

  /// Display name; falls back to [id].
  final String name;

  /// Language code (`en`, `pl`, `all`); empty when unknown.
  final String lang;

  /// `native` | `suwayomi` | `plugin` | `local`; empty when unknown.
  final String origin;

  /// When the evaluator last measured this source.
  final DateTime? probedAt;

  /// Uptime block.
  final UptimeMetric? uptime;

  /// Latency block (`latencyMs` on the wire).
  final LatencyMetric? latency;

  /// Blocking block.
  final BlockingMetric? blocking;

  /// Coverage block.
  final CoverageMetric? coverage;

  /// Chapter completeness block (`chapterCompleteness` on the wire).
  final CompletenessMetric? completeness;

  /// Image quality block.
  final ImageQualityMetric? imageQuality;

  /// Set when the source is a subset of a better one.
  final SubsetOfMetric? subsetOf;

  /// Which implementations of the site exist (native, JS, Keiyoushi).
  final AvailabilityMetric? availability;

  /// Weighted score in 0..1.
  final double? score;

  /// 1-based rank; null when unranked.
  final int? rank;

  /// Evaluator verdict.
  final HealthVerdict verdict;

  /// Machine reason codes (`uptime<0.95`, `blocking`, `coverage<0.60`,
  /// `subset`); see `cut_reasons.dart` for the plain-words version.
  final List<String> cutReasons;

  /// Visible warnings that do not cut the source (§5 `flags`, additive: a
  /// record from an older evaluator has none). Unknown entries are kept.
  final List<String> flags;

  /// True when the source needs a browser engine Kartka does not ship.
  bool get needsBrowserEngine => flags.contains(needsBrowserEngineFlag);

  /// The §5 JSON, omitting fields that are missing.
  Map<String, Object?> toJson() => compact({
    'id': id,
    'name': name,
    'lang': lang.isEmpty ? null : lang,
    'origin': origin.isEmpty ? null : origin,
    'probedAt': probedAt?.toUtc().toIso8601String(),
    'uptime': uptime?.toJson(),
    'latencyMs': latency?.toJson(),
    'blocking': blocking?.toJson(),
    'coverage': coverage?.toJson(),
    'chapterCompleteness': completeness?.toJson(),
    'imageQuality': imageQuality?.toJson(),
    'subsetOf': subsetOf?.toJson(),
    'availability': availability?.toJson(),
    'score': score,
    'rank': rank,
    'verdict': verdict.name,
    'cutReasons': cutReasons.isEmpty ? null : cutReasons,
    'flags': flags.isEmpty ? null : flags,
  });

  @override
  bool operator ==(Object other) =>
      other is SourceHealthRecord &&
      other.id == id &&
      other.name == name &&
      other.lang == lang &&
      other.origin == origin &&
      other.probedAt == probedAt &&
      other.uptime == uptime &&
      other.latency == latency &&
      other.blocking == blocking &&
      other.coverage == coverage &&
      other.completeness == completeness &&
      other.imageQuality == imageQuality &&
      other.subsetOf == subsetOf &&
      other.availability == availability &&
      other.score == score &&
      other.rank == rank &&
      other.verdict == verdict &&
      listEquals(other.cutReasons, cutReasons) &&
      listEquals(other.flags, flags);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    lang,
    origin,
    probedAt,
    uptime,
    latency,
    blocking,
    coverage,
    completeness,
    imageQuality,
    subsetOf,
    availability,
    score,
    rank,
    verdict,
    Object.hashAll(cutReasons),
    Object.hashAll(flags),
  );

  @override
  String toString() => 'SourceHealthRecord($id, rank: $rank, $verdict)';
}
