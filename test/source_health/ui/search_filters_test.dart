import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../fixtures.dart';
import 'harness.dart';

final List<String> _ids = [for (final r in fixtureRecords()) r.id];

Future<void> pumpTab(WidgetTester tester) async {
  tallSurface(tester);
  await tester.pumpWidget(
    host(
      SourcesTab(
        feed: FixtureSourceHealthFeed(fixtureJson('records.json')),
        clock: () => DateTime.utc(2026, 10, 25),
      ),
    ),
  );
  await tester.pump();
}

Future<void> typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search')), text);
  await tester.pumpAndSettle();
}

Future<void> setMinScore(WidgetTester tester, double v) async {
  tester.widget<Slider>(find.byKey(const Key('min-score'))).onChanged!(v);
  await tester.pumpAndSettle();
}

String counts(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('counts'))).data!;

void main() {
  testWidgets('fuzzy search narrows and ranks; clearing restores', (
    tester,
  ) async {
    await pumpTab(tester);
    await typeSearch(tester, 'mangdex');
    expect(cardOrder(tester, _ids), [
      'mangadex',
      'suwayomi:2499283573021220255',
    ]);
    expect(counts(tester), endsWith('showing 2'));
    await typeSearch(tester, 'CLOUDFLARE');
    expect(cardOrder(tester, _ids), ['plugin:comick']);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(6));
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(counts(tester), endsWith('showing 6'));
  });

  testWidgets('search finds rendered metrics and reasons in words', (
    tester,
  ) async {
    await pumpTab(tester);
    await typeSearch(tester, 'redundant');
    expect(cardOrder(tester, _ids), ['suwayomi:2499283573021220255']);
    await typeSearch(tester, 'zzzz');
    expect(cardOrder(tester, _ids), isEmpty);
    expect(find.text('No sources match these filters.'), findsOne);
  });

  testWidgets('reason chips: any selected reason, ANDed with verdicts', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Low coverage'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), ['suwayomi:1111', 'plugin:comick']);
    await tester.tap(find.widgetWithText(FilterChip, 'Subset'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(3));
    await tester.tap(find.widgetWithText(FilterChip, 'Low coverage'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Subset'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(6));
    for (final label in ['Blocking', 'Low uptime', 'Browser engine']) {
      expect(find.widgetWithText(FilterChip, label), findsOne);
    }
  });

  testWidgets('minimum score slider combines with search', (tester) async {
    await pumpTab(tester);
    expect(find.text('Min score 0.00'), findsOne);
    await setMinScore(tester, 0.85);
    expect(find.text('Min score 0.85'), findsOne);
    expect(cardOrder(tester, _ids), ['mangadex', 'local']);
    await typeSearch(tester, 'local');
    expect(cardOrder(tester, _ids), ['local']);
    expect(counts(tester), endsWith('showing 1'));
  });
}
