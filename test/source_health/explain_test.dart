import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/thresholds.dart';

import 'fixtures.dart';

void main() {
  group('thresholds (§5)', () {
    test('match the contract values', () {
      expect(HealthThresholds.minUptimeRatio, 0.95);
      expect(HealthThresholds.maxChallengeRate, 0);
      expect(HealthThresholds.minCoverageRatio, 0.60);
      expect(HealthThresholds.subsetOverlap, 0.50);
      expect(HealthThresholds.subsetPenalty, 0.5);
      expect(HealthThresholds.hardChallengeRate, 0.5);
      expect(HealthThresholds.completeChapterRatio, 0.8);
      expect(HealthThresholds.legacyCoverageShare, 0.6);
      expect(HealthThresholds.fullWidthPx, 1067);
      expect(defaultScoringProfile.keepScore, 0.90);
      expect(HealthThresholds.uptimeProbesTarget, 28);
      expect(HealthThresholds.staleAfter, const Duration(days: 8));
      expect(defaultScoringProfile.weights.total, closeTo(1, 1e-9));
    });
  });

  group('explainCutReasons', () {
    test('turns every §5 code into a plain sentence with the numbers', () {
      final r = fixtureRecord('plugin:comick');
      final words = explainCutReasons(r);
      expect(words, hasLength(3));
      expect(words[0], contains('22 of 28'));
      expect(words[0], contains('95 %'));
      expect(words[1], contains('Cloudflare challenge'));
      expect(words[1], contains('429 Too Many Requests'));
      expect(words[1], contains('35 %'));
      expect(words[2], contains('300 of 650'));
      expect(words[2], contains('60 %'));
    });

    test('subset names the covering source and the overlap', () {
      final words = explainCutReasons(
        fixtureRecord('suwayomi:2499283573021220255'),
        nameOf: (id) => id == 'mangadex' ? 'MangaDex (native)' : null,
      );
      expect(words.single, contains('93 %'));
      expect(words.single, contains('MangaDex (native)'));
      expect(words.single, contains('Its score is multiplied by 0.5'));
    });

    test('hard-filter codes cut whatever the score', () {
      const r = SourceHealthRecord(
        id: 'x',
        name: 'x',
        blocking: BlockingMetric(
          challengeRate: 0.6,
          kinds: ['cloudflare'],
          hardRate: 0.6,
        ),
        cutReasons: ['unreachable', 'blocking>=0.50'],
      );
      final words = explainCutReasons(r);
      expect(words[0], startsWith('Unreachable'));
      expect(words[1], contains('Cloudflare challenge'));
      expect(words[1], contains('At 50 % of requests or more'));
      expect(words, everyElement(contains('whatever it scores')));
    });

    test('falls back to generic words when the metric block is missing', () {
      const r = SourceHealthRecord(
        id: 'x',
        name: 'x',
        cutReasons: ['uptime<0.95', 'blocking', 'coverage<0.60', 'subset', 'z'],
      );
      final words = explainCutReasons(r);
      expect(words[0], contains('95 %'));
      expect(words[1], contains('challenge'));
      expect(words[2], contains('60 %'));
      expect(words[3], contains('another source'));
      expect(words[4], 'Other reason: z');
    });

    test('subset without an overlap figure quotes the threshold', () {
      const r = SourceHealthRecord(
        id: 'x',
        name: 'x',
        subsetOf: SubsetOfMetric(sourceId: 'mangadex'),
        cutReasons: ['subset'],
      );
      expect(
        explainCutReasons(r).single,
        contains('at least 50 % of its titles are also on mangadex'),
      );
      expect(explainCutReasons(r).single, isNot(contains('multiplied')));
    });

    test('blocking kinds read as words, unknown kinds verbatim', () {
      expect(describeBlockingKind('captcha'), 'captcha');
      expect(describeBlockingKind('403'), '403 Forbidden');
      expect(describeBlockingKind('teapot'), 'teapot');
    });
  });

  group('scoreBreakdown', () {
    test('pagesLoad multiplies the weighted sum (§5 score)', () {
      final r = fixtureRecord('suwayomi:2499283573021220255');
      final sum = scoreBreakdown(r)
          .fold<double>(0, (s, p) => s + (p.points ?? 0));
      expect(pagesLoadFactor(r), isNull);
      // Its published 93 % subset overlap multiplies by 1 − .5 × .93.
      final subset = subsetFactor(r)!;
      expect(subset, closeTo(0.535, 1e-9));
      expect(recomputedScore(r), closeTo(sum * subset, 1e-9));
      final halved = SourceHealthRecord.fromJson({
        ...r.toJson(),
        'pagesLoad': {'ratio': 0.5, 'sampled': 10},
      })!;
      expect(pagesLoadFactor(halved), 0.5);
      expect(recomputedScore(halved), closeTo(sum * 0.5 * subset, 1e-9));
      final unmeasured = SourceHealthRecord.fromJson({
        ...r.toJson(),
        'pagesLoad': {'sampled': 0},
      })!;
      expect(pagesLoadFactor(unmeasured), isNull);
      expect(recomputedScore(unmeasured), closeTo(sum * subset, 1e-9));
    });

    test('recomputes the §5 score from the metrics', () {
      final r = fixtureRecord('suwayomi:2499283573021220255');
      final parts = scoreBreakdown(r);
      expect(parts.map((p) => p.label), [
        'Coverage',
        'Uptime',
        'Image quality',
        'Latency',
      ]);
      final total = parts.fold<double>(0, (s, p) => s + (p.points ?? 0));
      // A run before the merged coverage: .5*(.6*.788 + .4*.97) + .2*.964
      // + .15*1 (1100 px >= 1067) + .15*(1-1300/5000) = 0.8842, as score.py.
      expect(total, closeTo(0.8842, 1e-9));
      expect(parts[0].normalized, closeTo(0.6 * 0.788 + 0.4 * 0.97, 1e-9));
      expect(parts[2].normalized, 1);
    });

    test('caps image width and latency, and leaves missing parts null', () {
      const r = SourceHealthRecord(
        id: 'x',
        name: 'x',
        latency: LatencyMetric(p95: 9000),
        imageQuality: ImageQualityMetric(medianWidthPx: 2800),
      );
      final parts = scoreBreakdown(r);
      expect(parts[0].normalized, isNull);
      expect(parts[0].points, isNull);
      expect(parts[2].normalized, 1);
      expect(parts[3].normalized, 0);
    });
  });
}
