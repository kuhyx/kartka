/// RTDB `/kartka-e2e/source_health_meta`: one evaluator run's totals, so the
/// Sources screen can say how many candidates were tested and which were
/// skipped before testing.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/source_health/model/json_read.dart';
import 'package:kartka/source_health/scoring/profile.dart';

/// The run summary. Every field is optional: the evaluator is another
/// program, and a field of the wrong type reads as missing.
@immutable
class SourceHealthMeta {
  /// Creates a summary.
  const new({
    this.runId,
    this.generatedAt,
    this.candidates,
    this.tested,
    this.verdicts,
    this.profile,
    this.skipped = const [],
  });

  /// Parses the node; null unless [json] is a map (absent on older runs).
  static SourceHealthMeta? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    final skipped = m['skipped'];
    return SourceHealthMeta(
      runId: readString(m, 'runId'),
      generatedAt: readInstant(m, 'generatedAt'),
      candidates: readInt(m, 'candidates'),
      tested: readInt(m, 'tested'),
      verdicts: VerdictCounts.fromJson(m['verdicts']),
      profile: ScoringProfile.fromJson(m['profile']),
      skipped: skipped is List
          ? List.unmodifiable(skipped.map(SkippedGroup.fromJson).nonNulls)
          : const [],
    );
  }

  /// The evaluator run this summarises.
  final String? runId;

  /// When the run finished.
  final DateTime? generatedAt;

  /// Sources the evaluator considered.
  final int? candidates;

  /// Sources actually tested (the rest are in [skipped]).
  final int? tested;

  /// Verdict totals over the tested sources.
  final VerdictCounts? verdicts;

  /// The scoring profile the run was judged with; null on runs before
  /// profiles (judged with DEFAULT) or when the node is invalid.
  final ScoringProfile? profile;

  /// Candidates left untested, grouped by index and reason.
  final List<SkippedGroup> skipped;

  /// This summary with [verdicts] replaced (recounted after a re-score).
  SourceHealthMeta withVerdicts(VerdictCounts verdicts) => SourceHealthMeta(
    runId: runId,
    generatedAt: generatedAt,
    candidates: candidates,
    tested: tested,
    verdicts: verdicts,
    profile: profile,
    skipped: skipped,
  );

  /// The JSON node, omitting missing fields.
  Map<String, Object?> toJson() => compact({
    'runId': runId,
    'generatedAt': generatedAt?.toUtc().toIso8601String(),
    'candidates': candidates,
    'tested': tested,
    'verdicts': verdicts?.toJson(),
    'profile': profile == null
        ? null
        : {'name': profile!.name, ...profile!.toJson()},
    'skipped': [for (final g in skipped) g.toJson()],
  });

  @override
  bool operator ==(Object other) =>
      other is SourceHealthMeta &&
      other.runId == runId &&
      other.generatedAt == generatedAt &&
      other.candidates == candidates &&
      other.tested == tested &&
      other.verdicts == verdicts &&
      other.profile == profile &&
      listEquals(other.skipped, skipped);

  @override
  int get hashCode => Object.hash(
    runId,
    generatedAt,
    candidates,
    tested,
    verdicts,
    profile,
    Object.hashAll(skipped),
  );
}

/// Keep / cut / pending totals.
@immutable
class VerdictCounts {
  /// Creates totals.
  const new({this.keep = 0, this.cut = 0, this.pending = 0});

  /// Parses `verdicts`; null unless a map, missing entries count 0.
  static VerdictCounts? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return VerdictCounts(
      keep: readInt(m, 'keep') ?? 0,
      cut: readInt(m, 'cut') ?? 0,
      pending: readInt(m, 'pending') ?? 0,
    );
  }

  /// Sources kept.
  final int keep;

  /// Sources cut.
  final int cut;

  /// Sources still pending.
  final int pending;

  /// The JSON block.
  Map<String, Object?> toJson() => {
    'keep': keep,
    'cut': cut,
    'pending': pending,
  };

  @override
  bool operator ==(Object other) =>
      other is VerdictCounts &&
      other.keep == keep &&
      other.cut == cut &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(keep, cut, pending);
}

/// Candidates from one index skipped for one reason.
@immutable
class SkippedGroup {
  /// Creates a group.
  const new({
    required this.index,
    required this.reason,
    this.count = 0,
    this.names = const [],
  });

  /// Parses one `skipped` entry; null unless a map.
  static SkippedGroup? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return SkippedGroup(
      index: readString(m, 'index') ?? '',
      reason: readString(m, 'reason') ?? '',
      count: readInt(m, 'count') ?? 0,
      names: readStrings(m, 'names'),
    );
  }

  /// The extension index the candidates came from.
  final String index;

  /// Why they were not tested.
  final String reason;

  /// How many were skipped.
  final int count;

  /// Their names (may be fewer than [count]).
  final List<String> names;

  /// The JSON entry.
  Map<String, Object?> toJson() => {
    'index': index,
    'reason': reason,
    'count': count,
    'names': names,
  };

  @override
  bool operator ==(Object other) =>
      other is SkippedGroup &&
      other.index == index &&
      other.reason == reason &&
      other.count == count &&
      listEquals(other.names, names);

  @override
  int get hashCode => Object.hash(index, reason, count, Object.hashAll(names));
}
