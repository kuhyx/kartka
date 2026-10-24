import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/metrics.dart';

import 'fixtures.dart';

void main() {
  test('contract example renders every metric', () {
    final r = fixtureRecord('suwayomi:2499283573021220255');
    expect(uptimeText(r.uptime), '96 % (27/28)');
    expect(latencyText(r.latency), 'p50 420 ms · p95 1.3 s');
    expect(blockingText(r.blocking), 'none');
    expect(coverageText(r.coverage), '512/650 (79 %)');
    expect(completenessText(r.completeness), '97 % over 40 titles');
    expect(imageWidthText(r.imageQuality), '1100 px');
    expect(jpegQualityText(r.imageQuality), 'q88');
    expect(scoreText(r.score), '0.81');
    expect(availabilityText(r.availability), 'native · JS plugin · Suwayomi');
  });

  test('availability lists only what exists', () {
    final r = fixtureRecord('plugin:comick');
    expect(availabilityText(r.availability), 'JS plugin');
    expect(availabilityText(const AvailabilityMetric(native: false)), 'none');
    expect(availabilityText(null), notMeasured);
    expect(availabilityText(const AvailabilityMetric()), notMeasured);
  });

  test('accruing uptime shows n/28 probes', () {
    final r = fixtureRecord('suwayomi:7034581279101437511');
    expect(uptimeText(r.uptime), 'accruing 9/28 probes');
    expect(uptimeText(const UptimeMetric()), 'accruing 0/28 probes');
  });

  test('blocking lists the kinds in words', () {
    final r = fixtureRecord('plugin:comick');
    expect(
      blockingText(r.blocking),
      '35 % (Cloudflare challenge, 429 Too Many Requests)',
    );
    expect(
      blockingText(const BlockingMetric(kinds: ['captcha'])),
      '— (captcha)',
    );
  });

  test('missing metrics and fields read as a dash or ?', () {
    expect(uptimeText(null), notMeasured);
    expect(
      uptimeText(const UptimeMetric(status: UptimeStatus.finalized)),
      '— (?/?)',
    );
    expect(latencyText(null), notMeasured);
    expect(latencyText(const LatencyMetric(p50: 5)), 'p50 5 ms · p95 —');
    expect(blockingText(null), notMeasured);
    expect(blockingText(const BlockingMetric()), notMeasured);
    expect(coverageText(null), notMeasured);
    expect(coverageText(const CoverageMetric()), '?/? (—)');
    expect(completenessText(null), notMeasured);
    expect(completenessText(const CompletenessMetric()), notMeasured);
    expect(imageWidthText(null), notMeasured);
    expect(jpegQualityText(null), notMeasured);
    expect(scoreText(null), notMeasured);
  });

  test('instant formats in UTC', () {
    expect(instant(DateTime.utc(2026, 10, 4, 9, 5)), '2026-10-04 09:05 UTC');
  });
}
