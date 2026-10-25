// The real W43 records in test/fixtures/source_health/w43_schema.json: the
// new app reads what the new evaluator added (install info, the hard
// filter) and re-scores each record to exactly its published judgement.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';

final _w43 = jsonDecode(
  File('test/fixtures/source_health/w43_schema.json').readAsStringSync(),
) as Map<String, Object?>;

List<SourceHealthRecord> _records(String run) => [
  for (final r in (_w43[run]! as Map)['records'] as List<Object?>)
    SourceHealthRecord.fromJson(r)!,
];

void main() {
  final byId = {for (final r in _records('new')) r.id: r};

  test('a Suwayomi source carries its extension package', () {
    final atsumaru = byId['suwayomi:2327480808438768017']!;
    expect(atsumaru.pkg, 'eu.kanade.tachiyomi.extension.en.atsumaru');
    expect(atsumaru.plugin, isNull);
    expect(atsumaru.verdict, HealthVerdict.keep);
  });

  test('a Mangayomi source carries its plugin and repo', () {
    final plugin = byId['plugin:mangayomi-955190069']!;
    expect(plugin.pkg, isNull);
    expect(plugin.plugin?.id, 'mangayomi-955190069');
    expect(plugin.plugin?.repo, endsWith('/index.json'));
  });

  test('hard-filter records are cut', () {
    final walled = byId['suwayomi:4972933717624256217']!;
    expect(walled.cutReasons, contains('blocking>=0.50'));
    expect(walled.blocking?.hardRate, greaterThanOrEqualTo(0.5));
    final dead = byId['suwayomi:4006397036545425884']!;
    expect(dead.unreachable, isTrue);
    expect(dead.cutReasons, contains('unreachable'));
    expect([walled.verdict, dead.verdict], everyElement(HealthVerdict.cut));
  });

  test('a W43 run has no chapter lists, so coverage stays the old one', () {
    expect(byId.values.map((r) => r.coverage?.completeRatio).nonNulls, isEmpty);
  });

  test('re-scoring under DEFAULT reproduces every published judgement', () {
    final published = _records('new');
    for (final r in rescore(published, defaultScoringProfile)) {
      final p = byId[r.id]!;
      expect(
        (r.score, r.defaultScore, r.verdict),
        (p.score, p.defaultScore, p.verdict),
        reason: r.id,
      );
    }
  });

  test('the old records re-score under the new rules without throwing', () {
    final ranked = rescore(_records('old'), defaultScoringProfile);
    expect(ranked.map((r) => r.rank), [for (var i = 1; i <= 7; i++) i]);
    expect(ranked.first.id, 'suwayomi:2327480808438768017');
  });
}
