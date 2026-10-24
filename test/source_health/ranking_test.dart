import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';

import 'fixtures.dart';

List<String> ids(List<SourceHealthRecord> rs) => [for (final r in rs) r.id];

void main() {
  final all = fixtureRecords();

  test('default query ranks by rank, unranked last', () {
    expect(ids(const HealthQuery().apply(all)), [
      'mangadex',
      'local',
      'suwayomi:2499283573021220255',
      'suwayomi:1111',
      'plugin:comick',
      'suwayomi:7034581279101437511',
    ]);
  });

  test('every sort puts the best first and missing values last', () {
    for (final sort in HealthSort.values) {
      final sorted = HealthQuery(sort: sort).apply(all);
      final keys = [for (final r in sorted) sort.keyOf(r)];
      final present = keys.whereType<Comparable<Object>>().toList();
      expect(keys.sublist(present.length).every((k) => k == null), isTrue,
          reason: '$sort puts nulls last');
      for (var i = 1; i < present.length; i++) {
        final c = present[i - 1].compareTo(present[i]);
        expect(sort.higherIsBetter ? c >= 0 : c <= 0, isTrue,
            reason: '$sort order at $i');
      }
      expect(sort.label, isNotEmpty);
    }
  });

  test('reversed flips the order but keeps missing values last', () {
    final q = const HealthQuery(sort: HealthSort.coverage).copyWith(
      reversed: true,
    );
    final sorted = ids(q.apply(all));
    expect(sorted.first, 'suwayomi:1111');
    expect(sorted.last, 'suwayomi:7034581279101437511');
  });

  test('ties break by name so the order is stable', () {
    final q = const HealthQuery(sort: HealthSort.uptime);
    expect(ids(q.apply(all)).take(3), [
      'local',
      'mangadex',
      'suwayomi:7034581279101437511',
    ]);
  });

  test('filters by verdict, lang and origin', () {
    expect(
      ids(const HealthQuery(verdicts: {HealthVerdict.keep}).apply(all)),
      ['mangadex', 'local'],
    );
    expect(ids(const HealthQuery(lang: 'pl').apply(all)), [
      'suwayomi:7034581279101437511',
    ]);
    final q = const HealthQuery().copyWith(
      origin: 'suwayomi',
      verdicts: {HealthVerdict.cut},
    );
    expect(ids(q.apply(all)), [
      'suwayomi:2499283573021220255',
      'suwayomi:1111',
    ]);
    expect(q.copyWith(clearOrigin: true).origin, isNull);
    expect(q.copyWith(lang: 'en').copyWith(clearLang: true).lang, isNull);
  });

  test('facet values list the distinct langs and origins', () {
    expect(langsOf(all), ['all', 'en', 'pl']);
    expect(originsOf(all), ['local', 'native', 'plugin', 'suwayomi']);
  });

  group('staleness', () {
    final now = DateTime.utc(2026, 11);
    test('last evaluated is the newest probedAt', () {
      expect(lastEvaluated(all), DateTime.utc(2026, 10, 24, 12));
      expect(lastEvaluated(const []), isNull);
    });

    test('stale after 8 days, or when never evaluated', () {
      expect(isStale(DateTime.utc(2026, 10, 24), now), isFalse);
      expect(isStale(DateTime.utc(2026, 10, 23, 23), now), isTrue);
      expect(isStale(null, now), isTrue);
    });
  });
}
