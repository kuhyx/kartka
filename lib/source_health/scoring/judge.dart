/// Scores, ranks and judges records under a [ScoringProfile] (contract §5),
/// exactly as the evaluator's `score.py` does, so the app can re-rank live.
///
/// `subsetOf` and `cutReasons` stay as published: the subset relation needs
/// every source's found titles and the hard filter the run state, which only
/// the evaluator has. The app applies the published subset penalty (in
/// `recomputedScore`) and hard-filter codes.
library;

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/profile.dart';

/// [r]'s score under [profile], rounded to 3 places like the evaluator.
double scoreOf(SourceHealthRecord r, ScoringProfile profile) =>
    round3(recomputedScore(r, profile));

/// The evaluator's hard-filter codes: unreachable, or challenged (other than
/// for a browser engine) on half the requests or more. They cut whatever
/// the score and profile.
const Set<String> kHardCutCodes = {'unreachable', 'blocking>=0.50'};

/// [r]'s verdict for [score] under [profile]: a hard-filter code cuts; else
/// a cut switch the profile enables whose reason applies cuts; else
/// `keepScore` or more keeps; else pending while coverage is unmeasured;
/// else cut.
HealthVerdict verdictOf(
  SourceHealthRecord r,
  double score,
  ScoringProfile profile,
) {
  if (r.cutReasons.any(kHardCutCodes.contains)) return HealthVerdict.cut;
  if (applicableCuts(r).any(profile.cuts.contains)) return HealthVerdict.cut;
  if (score >= profile.keepScore) return HealthVerdict.keep;
  return r.coverage?.ratio == null ? HealthVerdict.pending : HealthVerdict.cut;
}

/// The cut switches that apply to [r], exactly as the evaluator's
/// `applicable_cuts`: from its published cut-reason codes, the
/// needs-browser-engine flag and a pages-load ratio of 0. Narrower than
/// [reasonsOf] (the filter chips), which also reads the blocking kinds.
Set<HealthReason> applicableCuts(SourceHealthRecord r) {
  bool code(String prefix) => r.cutReasons.any((c) => c.startsWith(prefix));
  return {
    if (code('blocking')) HealthReason.blocking,
    if (code('coverage')) HealthReason.coverage,
    if (code('uptime')) HealthReason.uptime,
    if (r.needsBrowserEngine) HealthReason.browserEngine,
    if (r.pagesLoad?.ratio == 0) HealthReason.pagesNeverLoad,
  };
}

const _originOrder = {'native': 0, 'suwayomi': 1, 'plugin': 2};

/// [records] re-scored under [profile], ranked (1 = best: score, then origin
/// native < suwayomi < plugin < other, then id) and judged, in rank order.
/// Each also carries its DEFAULT-profile `defaultScore`.
List<SourceHealthRecord> rescore(
  List<SourceHealthRecord> records,
  ScoringProfile profile,
) {
  final scored = [for (final r in records) (r, scoreOf(r, profile))]
    ..sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byOrigin = _origin(a.$1).compareTo(_origin(b.$1));
      return byOrigin != 0 ? byOrigin : a.$1.id.compareTo(b.$1.id);
    });
  return List.unmodifiable([
    for (final (i, (r, score)) in scored.indexed)
      r.withJudgement(
        score: score,
        defaultScore: scoreOf(r, defaultScoringProfile),
        rank: i + 1,
        verdict: verdictOf(r, score, profile),
      ),
  ]);
}

int _origin(SourceHealthRecord r) => _originOrder[r.origin] ?? 9;

/// Keep / cut / pending totals of [records].
VerdictCounts countVerdicts(List<SourceHealthRecord> records) {
  int count(HealthVerdict v) => records.where((r) => r.verdict == v).length;
  return VerdictCounts(
    keep: count(HealthVerdict.keep),
    cut: count(HealthVerdict.cut),
    pending: count(HealthVerdict.pending),
  );
}
