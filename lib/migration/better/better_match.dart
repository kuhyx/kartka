/// Pure rules of "Migrate to better sources": which library entries should
/// move, to which sources, and which search result is the same series.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/source_health/fuzzy_match.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';

/// Why an entry on a source should move, or null when the source is fine:
/// not installed, failing its auto-install [flag], unreachable (or only
/// re-probed), cut, or hitting a challenge. A source without a [record]
/// (local files, legacy ids that are installed) stays.
String? moveReason({
  required SourceHealthRecord? record,
  required bool installed,
  String? flag,
}) {
  if (!installed) return 'its source is not installed';
  if (flag != null) return 'its source failed its test';
  final r = record;
  if (r == null) return null;
  if (r.unreachable || r.reprobedOnly) return 'its source is unreachable';
  if (r.verdict == HealthVerdict.cut) return 'its source is cut';
  if (rankTierReasons(r).contains('hits a challenge')) {
    return 'its source hits a challenge';
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

/// Lowest fuzzy score, in both directions, of a close title match.
const double closeTitleScore = 0.7;

final _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _words(String title) => title.replaceAll(_punctuation, ' ').trim();

/// How alike [a] and [b] are: the Sources search's fuzzy score of each as
/// a query against the other, the lower one (so a title only contained in
/// a longer one does not count); 0 when either misses.
double titleSimilarity(String a, String b) {
  final x = _words(a);
  final y = _words(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final there = FuzzyQuery(x).score([y], const []) ?? 0;
  final back = FuzzyQuery(y).score([x], const []) ?? 0;
  return math.min(there, back);
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
