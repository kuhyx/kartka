import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fixtures.dart';

void main() {
  group('SourceHealthRecord.fromJson', () {
    test('parses every §5 field of the contract example', () {
      final r = fixtureRecord('suwayomi:2499283573021220255');
      expect(r.name, 'MangaDex');
      expect(r.lang, 'en');
      expect(r.origin, 'suwayomi');
      expect(r.probedAt, DateTime.utc(2026, 10, 24, 12));
      expect(
        r.uptime,
        const UptimeMetric(
          windowDays: 7,
          probes: 28,
          ok: 27,
          ratio: 0.964,
          status: UptimeStatus.finalized,
        ),
      );
      expect(r.latency, const LatencyMetric(p50: 420, p95: 1300));
      expect(r.blocking, const BlockingMetric(challengeRate: 0, kinds: []));
      expect(
        r.coverage,
        const CoverageMetric(referenceSize: 650, found: 512, ratio: 0.788),
      );
      expect(
        r.completeness,
        const CompletenessMetric(sampled: 40, medianRatio: 0.97),
      );
      expect(
        r.imageQuality,
        const ImageQualityMetric(
          sampledPages: 120,
          medianWidthPx: 1100,
          medianJpegQuality: 88,
        ),
      );
      expect(
        r.subsetOf,
        const SubsetOfMetric(sourceId: 'mangadex', overlap: 0.93),
      );
      expect(r.score, 0.81);
      expect(r.rank, 3);
      expect(r.verdict, HealthVerdict.cut);
      expect(r.cutReasons, ['subset']);
    });

    test('pending record keeps missing metrics null', () {
      final r = fixtureRecord('suwayomi:7034581279101437511');
      expect(r.uptime!.status, UptimeStatus.accruing);
      expect(r.coverage, isNull);
      expect(r.completeness, isNull);
      expect(r.imageQuality, isNull);
      expect(r.subsetOf, isNull);
      expect(r.score, isNull);
      expect(r.rank, isNull);
      expect(r.cutReasons, isEmpty);
      expect(r.verdict, HealthVerdict.pending);
    });

    test('only id is required; everything else defaults', () {
      final r = SourceHealthRecord.fromJson({'id': 'x'})!;
      expect(r.name, 'x');
      expect(r.lang, '');
      expect(r.origin, '');
      expect(r.probedAt, isNull);
      expect(r.uptime, isNull);
      expect(r.latency, isNull);
      expect(r.blocking, isNull);
      expect(r.verdict, HealthVerdict.pending);
      expect(r.toJson(), {'id': 'x', 'name': 'x', 'verdict': 'pending'});
    });

    test('rejects non-maps and records without an id', () {
      expect(SourceHealthRecord.fromJson(null), isNull);
      expect(SourceHealthRecord.fromJson(const ['id']), isNull);
      expect(SourceHealthRecord.fromJson(const {'name': 'n'}), isNull);
      expect(SourceHealthRecord.fromJson(const {'id': ''}), isNull);
      expect(SourceHealthRecord.fromJson(const {'id': 3}), isNull);
    });

    test('wrong-typed fields read as missing instead of throwing', () {
      final r = SourceHealthRecord.fromJson(const {
        'id': 'x',
        'name': 5,
        'probedAt': 'not a date',
        'uptime': 'up',
        'latencyMs': {'p50': 'fast', 'p95': 12.6},
        'blocking': {'challengeRate': '0', 'kinds': 'cloudflare'},
        'subsetOf': {'overlap': 0.5},
        'score': true,
        'rank': 2.0,
        'cutReasons': ['blocking', 7],
      })!;
      expect(r.name, 'x');
      expect(r.probedAt, isNull);
      expect(r.uptime, isNull);
      expect(r.latency, const LatencyMetric(p95: 13));
      expect(r.blocking, const BlockingMetric(kinds: []));
      expect(r.subsetOf, isNull);
      expect(r.score, isNull);
      expect(r.rank, 2);
      expect(r.cutReasons, ['blocking']);
    });

    test('uptime status parses both wire values, missing = accruing', () {
      expect(UptimeMetric.fromJson(const {'status': 'final'})!.status,
          UptimeStatus.finalized);
      expect(UptimeMetric.fromJson(const {})!.status, UptimeStatus.accruing);
      expect(UptimeStatus.finalized.wire, 'final');
      expect(UptimeStatus.accruing.wire, 'accruing');
    });

    test('equal records share hashCode; toString names the id', () {
      final a = fixtureRecord('mangadex');
      final b = fixtureRecord('mangadex');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(fixtureRecord('local')));
      expect(a.toString(), contains('mangadex'));
    });
  });
}
