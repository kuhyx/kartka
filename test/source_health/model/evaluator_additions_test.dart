import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

void main() {
  group('pagesLoad', () {
    test('parses ratio and sampled; a null ratio stays null', () {
      final r = SourceHealthRecord.fromJson(const {
        'id': 'x',
        'pagesLoad': {'ratio': 0.92, 'sampled': 25},
      })!;
      expect(r.pagesLoad, const PagesLoadMetric(ratio: 0.92, sampled: 25));
      expect(
        PagesLoadMetric.fromJson(const {'ratio': null, 'sampled': 3}),
        const PagesLoadMetric(sampled: 3),
      );
    });

    test('absent or malformed reads as missing', () {
      expect(SourceHealthRecord.fromJson(const {'id': 'x'})!.pagesLoad, isNull);
      expect(PagesLoadMetric.fromJson('92 %'), isNull);
      expect(
        PagesLoadMetric.fromJson(const {'ratio': 'high', 'sampled': 'many'}),
        const PagesLoadMetric(),
      );
    });

    test('round-trips and compares by value', () {
      const m = PagesLoadMetric(ratio: 0.5, sampled: 10);
      expect(m.toJson(), {'ratio': 0.5, 'sampled': 10});
      expect(const PagesLoadMetric().toJson(), isEmpty);
      expect(PagesLoadMetric.fromJson(m.toJson()), m);
      expect(
        m.hashCode,
        const PagesLoadMetric(ratio: 0.5, sampled: 10).hashCode,
      );
      expect(m, isNot(const PagesLoadMetric(ratio: 0.5)));
    });
  });

  group('langScope', () {
    test('parses either value; absent is null', () {
      for (final scope in ['en+ja', 'unrestricted']) {
        final r = SourceHealthRecord.fromJson({'id': 'x', 'langScope': scope});
        expect(r!.langScope, scope);
      }
      expect(SourceHealthRecord.fromJson(const {'id': 'x'})!.langScope, isNull);
      expect(
        SourceHealthRecord.fromJson(const {'id': 'x', 'langScope': 3})!
            .langScope,
        isNull,
      );
    });
  });

  test('new fields take part in toJson, == and hashCode', () {
    const json = {
      'id': 'x',
      'name': 'X',
      'langScope': 'en+ja',
      'pagesLoad': {'ratio': 0.8, 'sampled': 5},
      'verdict': 'keep',
      'cutReasons': ['blocking'],
    };
    final a = SourceHealthRecord.fromJson(json)!;
    expect(a.toJson(), json);
    expect(SourceHealthRecord.fromJson(a.toJson()), a);
    expect(a.hashCode, SourceHealthRecord.fromJson(json)!.hashCode);
    expect(a, isNot(SourceHealthRecord.fromJson({...json, 'langScope': null})));
    expect(a, isNot(SourceHealthRecord.fromJson({...json, 'pagesLoad': null})));
  });
}
