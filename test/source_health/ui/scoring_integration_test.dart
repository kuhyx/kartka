import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/scoring/scored_feed.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/scoring_page.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import 'harness.dart';

SourceHealthRecord rec(
  String id, {
  double coverage = 1,
  double width = 1400,
  double? defaultScore,
  List<String> cutReasons = const [],
}) => SourceHealthRecord.fromJson({
  'id': id,
  'name': id,
  'origin': 'suwayomi',
  'coverage': {'ratio': coverage},
  'chapterCompleteness': {'medianRatio': 1},
  'uptime': {'ratio': 1, 'status': 'final'},
  'imageQuality': {'medianWidthPx': width},
  'latencyMs': {'p95': 0},
  'blocking': {'challengeRate': 0},
  'score': 0.9,
  'rank': 1,
  'verdict': 'keep',
  'defaultScore': ?defaultScore,
  'cutReasons': cutReasons,
})!;

void main() {
  late ControlledFeed base;
  late ScoringProfileStore store;
  late ScoredHealthFeed feed;

  Future<void> pump(WidgetTester tester) async {
    tallSurface(tester);
    base = ControlledFeed();
    store = ScoringProfileStore(
      SyncedKeyValueStore(
        MemoryKeyValueStore(),
        SettingsVault.plain,
        () => null,
      ),
    );
    await tester.runAsync(() => store.ready);
    feed = ScoredHealthFeed(base, store);
    await tester.pumpWidget(host(SourcesTab(feed: feed, scoring: store)));
    await tester.pump();
    base.controller.add([
      rec('a', width: 1000),
      rec('b', coverage: 0.4, cutReasons: ['coverage<0.60']),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the Scoring button opens the page; edits re-rank the tab', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Scoring · default'), findsOne);
    expect(cardOrder(tester, ['a', 'b']), ['a', 'b']);

    await tester.tap(find.byKey(const Key('open-scoring')));
    await tester.pumpAndSettle();
    expect(find.byType(ScoringPage), findsOne);
    await tester.tap(find.byKey(const Key('only-3')));
    await tester.pump();
    await tester.pump();
    Navigator.of(tester.element(find.byType(ScoringPage))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Scoring · custom'), findsOne);
    expect(cardOrder(tester, ['a', 'b']), ['b', 'a']);
    // The default scores (0.957 and 0.3 * 0.4 + 0.7) show next to the new.
    expect(find.byKey(const Key('default-score')), findsNWidgets(2));
    expect(find.text('default 0.96'), findsOne);
    expect(find.text('default 0.82'), findsOne);
  });

  test('Browse badges follow the active profile', () async {
    final base = ControlledFeed();
    final store = ScoringProfileStore(
      SyncedKeyValueStore(
        MemoryKeyValueStore(),
        SettingsVault.plain,
        () => null,
      ),
    );
    await store.ready;
    final feed = ScoredHealthFeed(base, store);
    final lookup = FeedSourceHealthLookup(feed);
    final seen = <Map<String, SourceHealthSummary>>[];
    final sub = lookup.watch().listen(seen.add);
    base.controller.add([
      rec('a'),
      rec('b', coverage: 0.4, cutReasons: ['coverage<0.60']),
    ]);
    await pumpEventQueue();
    expect(seen.last['b']!.verdict, HealthVerdict.keep);
    store.preview(
      const ScoringProfile(
        weights: ScoreWeights(
          coverage: 1,
          chapterCompleteness: 0,
          uptime: 0,
          imageQuality: 0,
          speed: 0,
        ),
        keepScore: 0.3,
        cuts: {HealthReason.coverage},
      ),
    );
    await pumpEventQueue();
    expect(
      (seen.last['a']!.verdict, seen.last['a']!.rank),
      (HealthVerdict.keep, 1),
    );
    expect(
      (seen.last['b']!.verdict, seen.last['b']!.rank),
      (HealthVerdict.cut, 2),
    );
    await sub.cancel();
  });

  testWidgets('the detail page explains the custom profile', (tester) async {
    tallSurface(tester);
    const profile = ScoringProfile(
      weights: ScoreWeights(
        coverage: 1,
        chapterCompleteness: 0,
        uptime: 0,
        imageQuality: 0,
        speed: 0,
      ),
      pagesLoadMultiplier: false,
      keepScore: 0.5,
      cuts: {HealthReason.subset},
    );
    final r = SourceHealthRecord.fromJson({
      ...rec('x', defaultScore: 0.7).toJson(),
      'score': 0.4,
      'pagesLoad': {'ratio': 0.5, 'sampled': 2},
      'cutReasons': ['subset'],
      'verdict': 'keep',
    })!;
    await tester.pumpWidget(
      host(
        SourceDetailPage(
          record: r,
          all: [r],
          now: DateTime.utc(2026, 10, 25),
          profile: profile,
        ),
      ),
    );
    expect(
      find.text('Score (custom profile) 0.40 · rank #1 · default 0.70'),
      findsOne,
    );
    expect(find.textContaining('custom scoring profile'), findsOne);
    expect(find.textContaining('unless a cut switch applies'), findsOne);
    expect(find.text('Kept on score ≥ 0.50 despite'), findsOne);
    expect(find.text('Pages load (multiplier)'), findsNothing);
    expect(find.text('100 %'), findsWidgets);
  });

  testWidgets('the reason filter offers "Pages never load"', (tester) async {
    await pump(tester);
    expect(find.text(HealthReason.pagesNeverLoad.label), findsOne);
  });
}
