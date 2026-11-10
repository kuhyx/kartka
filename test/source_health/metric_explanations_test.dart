import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import 'fixtures.dart';

Map<String, MetricExplanation> byTitle(SourceHealthRecord r) => {
  for (final e in explainMetrics(r)) e.semanticLabel: e,
};

void main() {
  test('one explanation per metric, each naming its threshold', () {
    final e = byTitle(fixtureRecord('mangadex'));
    expect(e.keys, [
      'Uptime',
      'Latency',
      'Blocking',
      'Coverage',
      'Chapter completeness',
      'Image quality',
      'Subset of another source',
      'Available as',
    ]);
    expect(e['Uptime']!.threshold, contains('95 %'));
    expect(e['Uptime']!.threshold, contains('28 probes'));
    expect(e['Latency']!.threshold, contains('5.0 s'));
    expect(e['Blocking']!.threshold, contains('0 %'));
    expect(e['Blocking']!.threshold, contains('50 % or more rules'));
    expect(e['Coverage']!.threshold, contains('60 %'));
    expect(e['Coverage']!.meaning, contains('80 % of its chapters'));
    expect(e['Image quality']!.threshold, contains('1067 px'));
    expect(e['Subset of another source']!.threshold, contains('50 %'));
    expect(
      e['Subset of another source']!.threshold,
      contains('multiplied by 1 − 0.5 × that share'),
    );
    for (final x in e.values) {
      expect(x.meaning, isNotEmpty);
      expect(x.value.isNotEmpty || x.origins != null, isTrue);
    }
    expect(e['Uptime']!.status, MetricStatus.pass);
    expect(e['Blocking']!.status, MetricStatus.pass);
    expect(e['Coverage']!.status, MetricStatus.pass);
    expect(e['Subset of another source']!.status, MetricStatus.pass);
    expect(e['Latency']!.status, MetricStatus.info);
    expect(e['Available as']!.origins, ['native', 'plugin', 'suwayomi']);
  });

  test('failing metrics are marked fail', () {
    final e = byTitle(fixtureRecord('plugin:comick'));
    expect(e['Uptime']!.status, MetricStatus.fail);
    expect(e['Blocking']!.status, MetricStatus.fail);
    expect(e['Coverage']!.status, MetricStatus.fail);
    final s = byTitle(fixtureRecord('suwayomi:2499283573021220255'));
    expect(s['Subset of another source']!.status, MetricStatus.fail);
    expect(s['Subset of another source']!.value, contains('mangadex'));
  });

  test('on a kept source, failing metrics only warn', () {
    final e = byTitle(
      SourceHealthRecord.fromJson(const {
        'id': 'k',
        'verdict': 'keep',
        'coverage': {'ratio': 0.4},
        'cutReasons': ['coverage<0.60'],
      })!,
    );
    expect(e['Coverage']!.status, MetricStatus.warn);
  });

  test('accruing uptime is pending, missing metrics are unknown', () {
    final e = byTitle(fixtureRecord('suwayomi:7034581279101437511'));
    expect(e['Uptime']!.status, MetricStatus.pending);
    expect(e['Coverage']!.status, MetricStatus.unknown);
    expect(e['Subset of another source']!.status, MetricStatus.unknown);
    expect(e['Image quality']!.status, MetricStatus.unknown);
    final bare = byTitle(const SourceHealthRecord(id: 'x', name: 'x'));
    expect(bare['Uptime']!.status, MetricStatus.unknown);
    expect(bare['Blocking']!.status, MetricStatus.unknown);
    expect(bare['Latency']!.status, MetricStatus.unknown);
    final noRatio = byTitle(
      const SourceHealthRecord(
        id: 'x',
        name: 'x',
        uptime: UptimeMetric(status: UptimeStatus.finalized),
        coverage: CoverageMetric(found: 3),
      ),
    );
    expect(noRatio['Uptime']!.status, MetricStatus.unknown);
    expect(noRatio['Coverage']!.status, MetricStatus.unknown);
  });
}
