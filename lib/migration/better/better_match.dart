/// Pure rules of "Migrate to better sources": which library entries should
/// move, to which sources, and which search result is the same series.
library;

import 'package:collection/collection.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';

/// Why an entry's source should be left; [label] is spoken, never painted.
enum MoveReason {
  /// The source is not installed.
  notInstalled('its source is not installed'),

  /// The source failed its auto-install test.
  failedTest('its source failed its test'),

  /// The source is unreachable (or only re-probed).
  unreachable('its source is unreachable'),

  /// The scored feed cut the source.
  cut('its source is cut'),

  /// The source hits a challenge page.
  challenge('its source hits a challenge');

  new(this.label);

  /// The reason in words, for screen readers.
  final String label;
}

/// Why an entry on a source should move, or null when the source is fine:
/// not installed, failing its auto-install [flag], unreachable (or only
/// re-probed), cut, or hitting a challenge. A source the evaluator
/// [rejected] for good (`meta.rejectedIds`) is cut, installed or not. Any
/// other source without a [record] (local files, installed legacy ids)
/// stays.
MoveReason? moveReason({
  required SourceHealthRecord? record,
  required bool installed,
  String? flag,
  bool rejected = false,
}) {
  if (rejected) return MoveReason.cut;
  if (!installed) return MoveReason.notInstalled;
  if (flag != null) return MoveReason.failedTest;
  final r = record;
  if (r == null) return null;
  if (r.unreachable || r.reprobedOnly) return MoveReason.unreachable;
  if (r.verdict == HealthVerdict.cut) return MoveReason.cut;
  if (rankTierReasons(r).contains('hits a challenge')) {
    return MoveReason.challenge;
  }
  return null;
}

/// One source an entry can move to.
typedef KeepTarget = ({SourceHealthRecord record, MangaSource source});

/// The installed `keep` sources of [records] without an auto-install flag,
/// best first: by rank (the scored feed's, rank tier included; unranked
/// last), then id.
List<KeepTarget> keepTargets(
  List<SourceHealthRecord> records,
  Map<String, MangaSource> installed, {
  required String? Function(String id) flagOf,
}) {
  final targets = <KeepTarget>[
    for (final r in records)
      if (r.verdict == HealthVerdict.keep && flagOf(r.id) == null)
        if (installed[r.id] case final s?) (record: r, source: s),
  ];
  int rankOf(KeepTarget t) => t.record.rank ?? 1 << 30;
  return targets..sort((a, b) {
    final byRank = rankOf(a).compareTo(rankOf(b));
    return byRank != 0 ? byRank : a.record.id.compareTo(b.record.id);
  });
}

/// The result of [items] that is [title]: an exact title first (case and
/// spacing aside), else the most similar one at [closeTitleScore] or more.
MangaSummary? titleMatch(String title, List<MangaSummary> items) {
  final exact = items.firstWhereOrNull((m) => isExactTitle(title, m.title));
  if (exact != null) return exact;
  MangaSummary? best;
  var bestScore = 0.0;
  for (final m in items) {
    final s = titleSimilarity(title, m.title);
    if (s >= closeTitleScore && s > bestScore) {
      best = m;
      bestScore = s;
    }
  }
  return best;
}
