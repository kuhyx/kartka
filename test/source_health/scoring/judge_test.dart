import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';

SourceHealthRecord rec({
  String id = 'x',
  String origin = 'suwayomi',
  double? coverage = 1,
  double? pages,
  Map<String, Object?> extra = const {},
}) => SourceHealthRecord.fromJson({
  'id': id,
  'origin': origin,
  'coverage': {'ratio': coverage},
  'chapterCompleteness': {'medianRatio': 1},
  'uptime': {'ratio': 1, 'status': 'final'},
  'imageQuality': {'medianWidthPx': 1400},
  'latencyMs': {'p95': 0},
  'blocking': {'challengeRate': 0},
  'pagesLoad': ?(pages == null ? null : {'ratio': pages, 'sampled': 4}),
  ...extra,
})!;

void main() {
  group('scoreOf', () {
    test('the default profile scores a pre-merge run as the evaluator', () {
      final r = rec(coverage: 0.788);
      final example = SourceHealthRecord.fromJson({
        ...r.toJson(),
        'chapterCompleteness': {'medianRatio': 0.97},
        'uptime': {'ratio': 0.964, 'status': 'final'},
        'imageQuality': {'medianWidthPx': 1100},
        'latencyMs': {'p95': 1300},
      })!;
      // score.py on the same record: .5 × (.6 × .788 + .4 × .97) + .2 × .964
      // + .15 × 1 (1100 px ≥ 1067) + .15 × (1 − 1300 / 5000).
      expect(scoreOf(example, defaultScoringProfile), 0.884);
    });

    test('weights are normalised, so only their ratios matter', () {
      final r = rec(coverage: 0.5);
      const a = ScoringProfile(
        weights: ScoreWeights(
          completeCoverage: 1,
          uptime: 1,
          imageQuality: 0,
          speed: 0,
        ),
      );
      const b = ScoringProfile(
        weights: ScoreWeights(uptime: 0.5, imageQuality: 0, speed: 0),
      );
      expect(scoreOf(r, a), 0.85);
      expect(scoreOf(r, b), 0.85);
    });

    test('the pages-load multiplier can be switched off', () {
      final r = rec(pages: 0.5);
      expect(scoreOf(r, defaultScoringProfile), 0.5);
      final off = defaultScoringProfile.copyWith(pagesLoadMultiplier: false);
      expect(scoreOf(r, off), 1.0);
      expect(scoreOf(rec(), defaultScoringProfile), 1.0);
    });

    test('an unmeasured part adds 0', () {
      expect(scoreOf(rec(coverage: null), defaultScoringProfile), 0.7);
    });

    test('rounds to three places like the evaluator', () {
      final r = rec(coverage: 0.3333333);
      expect(scoreOf(r, defaultScoringProfile), 0.8);
      expect(scoreOf(rec(coverage: 0.12345), defaultScoringProfile), 0.737);
    });
  });

  group('verdictOf', () {
    const p = defaultScoringProfile;

    test('score decides under the default profile', () {
      expect(verdictOf(rec(), 0.9, p), HealthVerdict.keep);
      expect(verdictOf(rec(), 0.899, p), HealthVerdict.cut);
      expect(verdictOf(rec(coverage: null), 0.2, p), HealthVerdict.pending);
      expect(verdictOf(rec(coverage: null), 0.95, p), HealthVerdict.keep);
    });

    test('keepScore comes from the profile', () {
      final low = p.copyWith(keepScore: 0.5);
      expect(verdictOf(rec(), 0.5, low), HealthVerdict.keep);
      expect(verdictOf(rec(), 0.49, low), HealthVerdict.cut);
    });

    test(
      'an enabled cut switch cuts a high score; a disabled one does not',
      () {
        final r = rec(
          extra: {
            'cutReasons': ['subset', 'uptime<0.95'],
            'flags': ['needs-browser-engine'],
          },
        );
        expect(verdictOf(r, 0.99, p), HealthVerdict.keep);
        for (final reason in [
          HealthReason.uptime,
          HealthReason.browserEngine,
        ]) {
          expect(
            verdictOf(r, 0.99, p.copyWith(cuts: {reason})),
            HealthVerdict.cut,
            reason: '$reason',
          );
        }
        // A subset is a graded penalty, never a switch; no blocking code.
        for (final reason in [HealthReason.subset, HealthReason.blocking]) {
          expect(
            verdictOf(r, 0.99, p.copyWith(cuts: {reason})),
            HealthVerdict.keep,
            reason: '$reason',
          );
        }
      },
    );

    test('pagesNeverLoad applies exactly when the ratio is 0', () {
      final cut = p.copyWith(cuts: {HealthReason.pagesNeverLoad});
      expect(verdictOf(rec(pages: 0), 0.99, cut), HealthVerdict.cut);
      expect(verdictOf(rec(pages: 0.1), 0.99, cut), HealthVerdict.keep);
      expect(verdictOf(rec(), 0.99, cut), HealthVerdict.keep);
    });
  });

  group('rescore', () {
    test('ranks by score, then origin native < suwayomi < plugin, then id', () {
      final ranked = rescore([
        rec(id: 'b', origin: 'plugin'),
        rec(id: 'a', origin: 'other'),
        rec(id: 'z', origin: 'native'),
        rec(id: 'y'),
        rec(id: 'w'),
        rec(id: 'low', coverage: 0.1),
      ], defaultScoringProfile);
      expect(ranked.map((r) => r.id), ['z', 'w', 'y', 'b', 'a', 'low']);
      expect(ranked.map((r) => r.rank), [1, 2, 3, 4, 5, 6]);
    });

    test('replaces score, defaultScore, rank and verdict; keeps the rest', () {
      final old = rec(
        extra: {'score': 0.1, 'rank': 9, 'verdict': 'cut', 'defaultScore': 0.2},
      );
      final one = rescore([old], defaultScoringProfile).single;
      expect(
        (one.score, one.defaultScore, one.rank, one.verdict),
        (1.0, 1.0, 1, HealthVerdict.keep),
      );
      expect(one.id, old.id);
      expect(one.coverage, old.coverage);
    });

    test('defaultScore stays the DEFAULT score under a custom profile', () {
      final only = defaultScoringProfile.copyWith(
        weights: const ScoreWeights(
          completeCoverage: 0,
          uptime: 0,
          imageQuality: 0,
        ),
      );
      final one = rescore([rec(pages: 0.5)], only).single;
      expect(one.score, 0.5);
      expect(one.defaultScore, 0.5);
      final slow = rescore([
        rec(
          extra: {
            'latencyMs': {'p95': 5000},
          },
        ),
      ], only).single;
      expect(slow.score, 0);
      expect(slow.defaultScore, 0.85);
    });
  });

  test('the breakdown shows the normalised weights and the profile', () {
    final p = defaultScoringProfile.copyWith(
      weights: const ScoreWeights(
        completeCoverage: 1,
        uptime: 1,
        imageQuality: 0,
        speed: 0,
      ),
    );
    final parts = scoreBreakdown(rec(), p);
    expect(parts.map((q) => q.weight), [0.5, 0.5, 0, 0]);
    expect(recomputedScore(rec(pages: 0.5), p), closeTo(0.5, 1e-9));
    expect(
      recomputedScore(rec(pages: 0.5), p.copyWith(pagesLoadMultiplier: false)),
      closeTo(1, 1e-9),
    );
  });
}
