// Schema compatibility (session 8): records and a profile in the new shape
// must parse, re-score and explain without throwing, and the real W43
// records and RTDB scoring values of the old and the new evaluator / app
// must read on either side. This file passes unchanged against bf9b3bc (the
// old APK's code), so the new evaluator output cannot crash that build; it
// keeps guarding the current code too.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';

final _shared = jsonDecode(
  File('test/fixtures/source_health/s8_schema.json').readAsStringSync(),
) as Map<String, Object?>;

final _w43 = jsonDecode(
  File('test/fixtures/source_health/w43_schema.json').readAsStringSync(),
) as Map<String, Object?>;

ScoringProfile? _setting(String key) =>
    ScoringProfile.fromJson(jsonDecode(_w43[key]! as String));

void main() {
  final raw = _shared['records']! as List<Object?>;

  test('every new-shape record parses with its id and metrics', () {
    final records = [for (final r in raw) SourceHealthRecord.fromJson(r)];
    expect(records.map((r) => r?.id), [
      'suwayomi:1',
      'suwayomi:2',
      'plugin:mangayomi-955190069',
    ]);
    expect(records[0]!.coverage?.ratio, 0.8);
    expect(records[1]!.subsetOf?.overlap, 0.62);
    expect(records[2]!.coverage?.ratio, isNull);
  });

  test('re-scoring, reasons and explanations never throw', () {
    final records = [for (final r in raw) SourceHealthRecord.fromJson(r)!];
    for (final profile in [
      defaultScoringProfile,
      ScoringProfile.fromJson(jsonDecode(_shared['profile']! as String))!,
    ]) {
      final ranked = rescore(records, profile);
      expect(ranked, hasLength(3));
      for (final r in ranked) {
        expect(r.score, inInclusiveRange(0, 1));
        reasonsOf(r);
        expect(explainCutReasons(r), hasLength(r.cutReasons.length));
        expect(SourceHealthRecord.fromJson(r.toJson())?.id, r.id);
      }
    }
  });

  group('W43', () {
    test('the old and the new RTDB scoring values read as DEFAULT', () {
      expect(_setting('oldProfile'), defaultScoringProfile);
      expect(_setting('newProfile'), defaultScoringProfile);
    });

    for (final run in ['old', 'new']) {
      final part = _w43[run]! as Map<String, Object?>;

      test('$run evaluator meta parses with its DEFAULT profile', () {
        final meta = SourceHealthMeta.fromJson(part['meta'])!;
        expect(meta.runId, '2026-W43');
        expect(meta.tested, 585);
        expect(meta.profile, defaultScoringProfile);
        expect(meta.skipped, isNotEmpty);
      });

      test('$run evaluator records parse, re-score and explain', () {
        final records = [
          for (final r in part['records']! as List<Object?>)
            SourceHealthRecord.fromJson(r)!,
        ];
        expect(records.map((r) => r.id), _w43['ids']);
        for (final profile in [
          defaultScoringProfile,
          _setting('oldProfile')!,
          _setting('newProfile')!,
        ]) {
          final ranked = rescore(records, profile);
          expect(ranked, hasLength(records.length));
          for (final r in ranked) {
            expect(r.score, inInclusiveRange(0, 1));
            reasonsOf(r);
            expect(explainCutReasons(r), hasLength(r.cutReasons.length));
            expect(SourceHealthRecord.fromJson(r.toJson())?.id, r.id);
          }
        }
      });
    }
  });
}
