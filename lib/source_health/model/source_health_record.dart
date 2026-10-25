/// The §5 source-health record (evaluator → RTDB → app UI).
library;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/json_read.dart';
import 'package:kartka/source_health/model/metrics.dart';

/// The §5 `flags` entry for a source whose extension needs a browser engine.
const needsBrowserEngineFlag = 'needs-browser-engine';

/// The §5 `flags` entry for a source the previous run hard-cut whose one
/// reachability request this run failed: only re-probed, not measured.
const reprobeOnlyFlag = 'reprobe-only';

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
    this.pagesLoad,
    this.langScope,
    this.score,
    this.defaultScore,
    this.rank,
    this.verdict = HealthVerdict.pending,
    this.cutReasons = const [],
    this.flags = const [],
    this.unreachable = false,
    this.pkg,
    this.plugin,
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
      pagesLoad: PagesLoadMetric.fromJson(j['pagesLoad']),
      langScope: readString(j, 'langScope'),
      score: readDouble(j, 'score'),
      defaultScore: readDouble(j, 'defaultScore'),
      rank: readInt(j, 'rank'),
      verdict: HealthVerdict.parse(readString(j, 'verdict')),
      cutReasons: readStrings(j, 'cutReasons'),
      flags: readStrings(j, 'flags'),
      unreachable: j['unreachable'] == true,
      pkg: readString(j, 'pkg'),
      plugin: PluginInstallRef.fromJson(j['plugin']),
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

  /// Share of sampled pages that actually loaded; absent from older runs.
  final PagesLoadMetric? pagesLoad;

  /// Languages the evaluator tested (`en+ja` | `unrestricted`); null when
  /// the run predates the field.
  final String? langScope;

  /// Weighted score in 0..1 under the active scoring profile.
  final double? score;

  /// The same score under the DEFAULT profile; null on runs before profiles.
  final double? defaultScore;

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

  /// The evaluator could not reach the source at all (hard cut; a source
  /// that only needed a browser engine is never marked). False when absent.
  final bool unreachable;

  /// Tachiyomi extension package of a `suwayomi` source; null otherwise.
  final String? pkg;

  /// The plugin (and its repo) reading a `plugin` source; null when none is
  /// installable (legacy sources).
  final PluginInstallRef? plugin;

  /// A copy with the judgement fields replaced (the scoring profile's
  /// re-score); every metric is kept.
  SourceHealthRecord withJudgement({
    required double score,
    required double defaultScore,
    required int rank,
    required HealthVerdict verdict,
  }) => SourceHealthRecord(
    id: id,
    name: name,
    lang: lang,
    origin: origin,
    probedAt: probedAt,
    uptime: uptime,
    latency: latency,
    blocking: blocking,
    coverage: coverage,
    completeness: completeness,
    imageQuality: imageQuality,
    subsetOf: subsetOf,
    availability: availability,
    pagesLoad: pagesLoad,
    langScope: langScope,
    score: score,
    defaultScore: defaultScore,
    rank: rank,
    verdict: verdict,
    cutReasons: cutReasons,
    flags: flags,
    unreachable: unreachable,
    pkg: pkg,
    plugin: plugin,
  );

  /// True when the source needs a browser engine Kartka does not ship.
  bool get needsBrowserEngine => flags.contains(needsBrowserEngineFlag);

  /// True when this run only re-probed the source (one failed request).
  bool get reprobedOnly => flags.contains(reprobeOnlyFlag);

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
    'pagesLoad': pagesLoad?.toJson(),
    'langScope': langScope,
    'score': score,
    'defaultScore': defaultScore,
    'rank': rank,
    'verdict': verdict.name,
    'cutReasons': cutReasons.isEmpty ? null : cutReasons,
    'flags': flags.isEmpty ? null : flags,
    'unreachable': unreachable ? true : null,
    'pkg': pkg,
    'plugin': plugin?.toJson(),
  });

  // Equal exactly when the §5 JSON is: toJson is lossless (fromJson ∘
  // toJson is the identity), and it keeps == in step with every new field.
  @override
  bool operator ==(Object other) =>
      other is SourceHealthRecord && _equality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => 'SourceHealthRecord($id, rank: $rank, $verdict)';
}

const _equality = DeepCollectionEquality();
