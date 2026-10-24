import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/thresholds.dart';

import 'fixtures.dart';

void main() {
  group('thresholds (§5)', () {
    test('match the contract values', () {
      expect(HealthThresholds.minUptimeRatio, 0.95);
      expect(HealthThresholds.maxChallengeRate, 0);
      expect(HealthThresholds.minCoverageRatio, 0.60);
      expect(HealthThresholds.subsetOverlap, 0.90);
      expect(HealthThresholds.uptimeProbesTarget, 28);
      expect(HealthThresholds.staleAfter, const Duration(days: 8));
      final weights = HealthThresholds.weightCoverage +
          HealthThresholds.weightCompleteness +
          HealthThresholds.weightUptime +
          HealthThresholds.weightImageQuality +
          HealthThresholds.weightLatency;
      expect(weights, closeTo(1, 1e-9));
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

    test('blocking kinds read as words, unknown kinds verbatim', () {
      expect(describeBlockingKind('captcha'), 'captcha');
      expect(describeBlockingKind('403'), '403 Forbidden');
      expect(describeBlockingKind('teapot'), 'teapot');
    });
  });

  group('scoreBreakdown', () {
    test('recomputes the §5 score from the metrics', () {
      final r = fixtureRecord('suwayomi:2499283573021220255');
      final parts = scoreBreakdown(r);
      expect(parts.map((p) => p.label), [
        'Coverage',
        'Chapter completeness',
        'Uptime',
        'Image quality',
        'Latency',
      ]);
      final total = parts.fold<double>(0, (s, p) => s + (p.points ?? 0));
      // 0.3*.788 + 0.2*.97 + 0.2*.964 + 0.15*(1100/1400) + 0.15*(1-1300/5000)
      // = 0.852. (The §5 example's "score": 0.81 is illustrative and does
      // not follow its own formula; the UI shows the evaluator's score.)
      expect(total, closeTo(0.852, 0.001));
      expect(parts[3].normalized, closeTo(1100 / 1400, 1e-9));
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
      expect(parts[3].normalized, 1);
      expect(parts[4].normalized, 0);
    });
  });
}
