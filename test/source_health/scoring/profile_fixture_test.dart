// Cross-check with the Python evaluator: both suites read
// tools/source_eval/tests/fixtures/scoring_profile.json, so the DEFAULT
// profile and the judgements cannot drift apart. Python derives cutReasons
// and subsetOf from the records + found; Dart re-ranks the published ones.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/thresholds.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';

final _shared = jsonDecode(
  File('tools/source_eval/tests/fixtures/scoring_profile.json')
      .readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object?> _map(Object? v) => (v! as Map).cast<String, Object?>();

ScoringProfile _named(String name) => name == 'default'
    ? defaultScoringProfile
    : ScoringProfile.fromJson(_map(_map(_shared['profiles'])[name]))!;

void main() {
  test('the DEFAULT profile is the shared one', () {
    expect(defaultScoringProfile.toJson(), _shared['default']);
    expect(ScoringProfile.fromJson(_shared['default']), defaultScoringProfile);
    expect(defaultScoringProfile.isDefault, isTrue);
    expect(defaultScoringProfile.name, 'default');
  });

  test('scale and thresholds are the shared ones', () {
    final scale = _map(_shared['scale']);
    expect(scale['fullWidthPx'], HealthThresholds.fullWidthPx);
    expect(scale['worstP95Ms'], HealthThresholds.worstP95Ms);
    final t = _map(_shared['thresholds']);
    expect(t['minUptime'], HealthThresholds.minUptimeRatio);
    expect(t['minCoverage'], HealthThresholds.minCoverageRatio);
    expect(t['subsetOverlap'], HealthThresholds.subsetOverlap);
    expect(t['subsetPenalty'], HealthThresholds.subsetPenalty);
    expect(t['hardChallengeRate'], HealthThresholds.hardChallengeRate);
    expect(t['completeChapterRatio'], HealthThresholds.completeChapterRatio);
    expect(t['legacyCoverageShare'], HealthThresholds.legacyCoverageShare);
    expect(_shared['hardCutCodes'], unorderedEquals(kHardCutCodes));
  });

  test('the setting key and its RTDB node are the shared ones', () {
    expect(_shared['settingKey'], kScoringSetting);
    expect(kSyncedSettings, contains(kScoringSetting));
    expect('kartka/${settingPath(kScoringSetting)}', _shared['settingNode']);
  });

  group('parse', () {
    for (final raw in _shared['parse']! as List<Object?>) {
      final c = _map(raw);
      test(c['name']! as String, () {
        final want = c['profile'] == null
            ? null
            : _named(c['profile']! as String);
        expect(ScoringProfile.fromJson(c['input']), want);
      });
    }
  });

  group('golden judgements', () {
    final records = [
      for (final r in _shared['records']! as List<Object?>)
        SourceHealthRecord.fromJson(r)!,
    ];
    final expected = _map(_shared['expect']);
    for (final name in expected.keys) {
      test(name, () {
        final want = _map(expected[name]);
        final ranked = rescore(records, _named(name));
        expect(ranked.map((r) => r.id), want['order']);
        expect(ranked.map((r) => r.rank), [
          for (var i = 1; i <= records.length; i++) i,
        ]);
        final judged = _map(want['judged']);
        final defaults = _map(_map(_map(expected['default'])['judged']));
        for (final r in ranked) {
          final w = judged[r.id]! as List<Object?>;
          expect(r.score, closeTo(w[0]! as num, 1e-9), reason: r.id);
          expect(r.verdict.name, w[1], reason: r.id);
          final d = defaults[r.id]! as List<Object?>;
          expect(r.defaultScore, closeTo(d[0]! as num, 1e-9), reason: r.id);
        }
      });
    }
  });
}
