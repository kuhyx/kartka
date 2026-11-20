/// Pure rules of duplicate merging (DOCS-spec "Duplicate merging"): which
/// library entries are literally the same series, and which one stays.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/migration/dedupe/dupe_facts.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/source_health/fuzzy_match.dart';

export 'package:kartka/migration/dedupe/dupe_facts.dart';

/// Lowest [SameManga.titleScore] of a duplicate pair: an exact title
/// (case, punctuation and `&` aside) or a near-exact one. Every word of
/// each title must match the other, so a sequel ("X 2") never pairs.
const double sameTitleScore = 0.95;

/// A [SameManga.descriptionScore] below this is "clearly different".
const double differentDescription = 0.2;

/// Whether [a] and [b] are the same series on two sources: the title
/// matches at [sameTitleScore], no evidence disagrees (authors when both
/// list some, chapter counts within 10 % or 3, descriptions when both have
/// one), and some evidence exists (an author or a description on either
/// side; none at all is uncertain, so skipped).
bool isDuplicate(Dupe a, Dupe b) {
  if (a.entry.sourceId == b.entry.sourceId) return false;
  final x = a.manga;
  final y = b.manga;
  final match = SameManga(x);
  if (match.titleScore(y) < sameTitleScore) return false;
  if (match.authorScore(y) == 0) return false;
  if (!_closeCounts(x.chapters!, y.chapters!)) return false;
  final description = match.descriptionScore(y);
  if (description != null && description < differentDescription) {
    return false;
  }
  return _hasEvidence(x) || _hasEvidence(y);
}

bool _closeCounts(int a, int b) {
  final diff = (a - b).abs();
  return diff <= 3 || diff <= 0.1 * math.max(a, b);
}

bool _hasEvidence(MangaFacts f) =>
    f.authors.any((a) => a.trim().isNotEmpty) ||
    (f.description?.trim().isNotEmpty ?? false);

const int _unranked = 1 << 30;

/// 0 keep, 1 pending, 2 cut; 3 when the source is not installed or has no
/// record (it always loses).
int _tier(Dupe d) => switch (d) {
  Dupe(installed: true, health: final h?) => switch (h.verdict) {
    HealthVerdict.keep => 0,
    HealthVerdict.pending => 1,
    HealthVerdict.cut => 2,
  },
  _ => 3,
};

/// Best first: keep before pending before cut before no record or not
/// installed, then the evaluator rank (ranked tiers only), then more
/// chapters, then the newer newest chapter, then the key. A total order,
/// so every device picks the same winner from the same facts.
int compareSuperior(Dupe a, Dupe b) {
  final ta = _tier(a);
  final tb = _tier(b);
  if (ta != tb) return ta.compareTo(tb);
  if (ta < 3) {
    final byRank = (a.health!.rank ?? _unranked).compareTo(
      b.health!.rank ?? _unranked,
    );
    if (byRank != 0) return byRank;
  }
  final byCount = b.facts.chapters.length.compareTo(a.facts.chapters.length);
  if (byCount != 0) return byCount;
  final na = a.newestUpload;
  final nb = b.newestUpload;
  if (na != nb) {
    if (na == null) return 1;
    if (nb == null) return -1;
    return nb.compareTo(na);
  }
  return a.entry.key.compareTo(b.entry.key);
}

/// One merge: its `losers` go onto its `winner`.
typedef DupeGroup = ({Dupe winner, List<Dupe> losers});

/// The merges among [all]: the best entry not yet merged takes every later
/// one that [isDuplicate] with it, checked directly against it (A~B and
/// B~C through B's unknown author do not make A~C). Pairs are only tried
/// within a bucket of the first word of a name, so a large library is not
/// compared all against all.
List<DupeGroup> planMerges(List<Dupe> all) {
  final sorted = [...all]..sort(compareSuperior);
  final words = [for (final d in sorted) _firstWords(d.manga)];
  final buckets = <String, List<int>>{};
  for (final (i, ws) in words.indexed) {
    for (final w in ws) {
      (buckets[w] ??= []).add(i);
    }
  }
  final taken = <int>{};
  final groups = <DupeGroup>[];
  for (final (i, winner) in sorted.indexed) {
    if (taken.contains(i)) continue;
    final near = SplayTreeSet<int>.of([
      for (final w in words[i])
        for (final j in buckets[w]!)
          if (j > i && !taken.contains(j)) j,
    ]);
    final losers = [
      for (final j in near)
        if (isDuplicate(winner, sorted[j])) j,
    ];
    if (losers.isEmpty) continue;
    taken.addAll(losers);
    groups.add((winner: winner, losers: [for (final j in losers) sorted[j]]));
  }
  return groups;
}

Set<String> _firstWords(MangaFacts f) => {
  for (final name in f.names)
    foldForSearch(name)
        .split(RegExp('[^a-z0-9]+'))
        .firstWhere((w) => w.isNotEmpty, orElse: () => ''),
};
