// Rank tiers (decision 2026-10-29): a source that needs a browser engine or
// hits a challenge ranks below every source without it, both lowest, without
// changing its score or verdict; the detail page says why.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

import '../../helpers/spoken_icon.dart';
import 'harness.dart';

SourceHealthRecord rec(
  String id, {
  double coverage = 1,
  bool browser = false,
  List<String> reasons = const [],
}) => SourceHealthRecord.fromJson({
  'id': id,
  'name': id,
  'origin': 'suwayomi',
  'coverage': {'ratio': coverage, 'completeRatio': coverage},
  'uptime': {'ratio': 1, 'status': 'final'},
  'imageQuality': {'medianWidthPx': 1400},
  'latencyMs': {'p95': 0},
  'blocking': {'challengeRate': 0},
  'flags': ?(browser ? [needsBrowserEngineFlag] : null),
  'cutReasons': reasons,
})!;

void main() {
  group('rankTier', () {
    test('counts a browser engine and a challenge', () {
      expect(rankTier(rec('a')), 0);
      expect(rankTier(rec('b', browser: true)), 1);
      expect(rankTier(rec('c', reasons: ['blocking'])), 1);
      expect(rankTier(rec('d', reasons: ['blocking>=0.50'])), 1);
      expect(rankTier(rec('e', browser: true, reasons: ['blocking'])), 2);
      expect(rankTierReasons(rec('e', browser: true, reasons: ['blocking'])), [
        'needs a browser engine',
        'hits a challenge',
      ]);
    });

    test('other reasons do not lower the tier', () {
      expect(rankTier(rec('a', reasons: ['uptime<0.95', 'subset'])), 0);
      expect(rankTierReasons(rec('a')), isEmpty);
    });
  });

  test('rescore ranks by tier first, keeping score and verdict', () {
    final ranked = rescore([
      rec('both', browser: true, reasons: ['blocking']),
      rec('kcef', browser: true),
      rec('cf', reasons: ['blocking']),
      rec('weak', coverage: 0.2),
      rec('good'),
    ], defaultScoringProfile);
    expect(ranked.map((r) => r.id), ['good', 'weak', 'cf', 'kcef', 'both']);
    final kcef = ranked.firstWhere((r) => r.id == 'kcef');
    expect(kcef.score, 1);
    expect(kcef.verdict, HealthVerdict.keep);
  });

  testWidgets('the score breakdown says why a source ranks low', (
    tester,
  ) async {
    tallSurface(tester);
    final r = rec('both', browser: true, reasons: ['blocking']);
    await tester.pumpWidget(
      host(SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 10))),
    );
    expect(
      spokenContaining(
        'Ranked lowest: it needs a browser engine and hits a challenge, so '
        'it ranks below every source with only one of these or neither. '
        'The rank only: score and verdict are unchanged.',
      ),
      findsOne,
    );
  });

  testWidgets('one reason ranks it below every source without it', (
    tester,
  ) async {
    tallSurface(tester);
    final r = rec('kcef', browser: true);
    await tester.pumpWidget(
      host(SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 10))),
    );
    expect(
      spokenContaining(
        'Ranked low: it needs a browser engine, so it ranks below every '
        'source that does not.',
      ),
      findsOne,
    );
  });

  test('the Blocking explanation names the rank penalty', () {
    final blocking = explainMetrics(rec('a'))
        .firstWhere((e) => e.semanticLabel == 'Blocking');
    expect(
      blocking.threshold,
      contains(
        'A challenge or a browser engine each ranks the source below every '
        'source without it, both lowest; neither changes the score.',
      ),
    );
  });

  testWidgets('no rank line for an unflagged source', (tester) async {
    tallSurface(tester);
    final r = rec('plain');
    await tester.pumpWidget(
      host(SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 10))),
    );
    expect(spokenContaining('Ranked low'), findsNothing);
    expect(find.byKey(const Key('recomputed')), findsOne);
  });
}
