import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../fixtures.dart';
import 'harness.dart';

final List<String> _ids = [for (final r in fixtureRecords()) r.id];

Future<void> pumpTab(WidgetTester tester, {DateTime? now}) async {
  tallSurface(tester);
  final at = now ?? DateTime.utc(2026, 10, 25);
  await tester.pumpWidget(
    host(
      SourcesTab(
        feed: FixtureSourceHealthFeed(fixtureJson('records.json')),
        clock: () => at,
      ),
    ),
  );
  await tester.pump();
}

Future<void> choose(WidgetTester tester, Key dropdown, String item) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ranks every source and shows every metric', (tester) async {
    await pumpTab(tester);
    expect(cardOrder(tester, _ids), [
      'mangadex',
      'local',
      'suwayomi:2499283573021220255',
      'suwayomi:1111',
      'plugin:comick',
      'suwayomi:7034581279101437511',
    ]);
    for (final text in [
      '96 % (27/28)',
      'accruing 9/28 probes',
      'p50 420 ms · p95 1.3 s',
      '35 % (Cloudflare challenge, 429 Too Many Requests)',
      '512/650 (79 %)',
      '97 % over 40 titles',
      '1100 px',
      'q88',
      'native · JS plugin · Suwayomi',
      '#3 Cut',
      'Pending',
      '0.81',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('Down too often: answered 22 of 28'), findsOne);
    expect(find.textContaining('Catalogue too small: has 90 of 650'), findsOne);
    expect(find.text('Subset of MangaDex (93 %)'), findsOne);
    expect(find.text('Last evaluated 2026-10-24 12:00 UTC'), findsOne);
    expect(find.textContaining('older than 8 days'), findsNothing);
  });

  testWidgets('warns when results are stale', (tester) async {
    await pumpTab(tester, now: DateTime.utc(2026, 11, 10));
    expect(find.textContaining('older than 8 days'), findsOne);
  });

  testWidgets('sorts by any metric, best first, and reverses', (tester) async {
    await pumpTab(tester);
    await choose(tester, const Key('sort'), 'Sort: Coverage');
    expect(cardOrder(tester, _ids).take(3), [
      'mangadex',
      'suwayomi:2499283573021220255',
      'local',
    ]);
    await tester.tap(find.byKey(const Key('reverse')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids).first, 'suwayomi:1111');
    expect(cardOrder(tester, _ids).last, 'suwayomi:7034581279101437511');
  });

  testWidgets('filters by verdict, language and origin', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Cut'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), [
      'suwayomi:2499283573021220255',
      'suwayomi:1111',
      'plugin:comick',
    ]);
    await choose(tester, const Key('origin'), 'JS plugin');
    expect(cardOrder(tester, _ids), ['plugin:comick']);
    await choose(tester, const Key('lang'), 'pl');
    expect(cardOrder(tester, _ids), isEmpty);
    expect(find.text('No sources match these filters.'), findsOne);
    await choose(tester, const Key('lang'), 'All languages');
    await choose(tester, const Key('origin'), 'All origins');
    await tester.tap(find.widgetWithText(FilterChip, 'Cut'));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(6));
  });

  testWidgets('a card opens its detail page; subset links to the other', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.text('Subset of MangaDex (93 %)'));
    await tester.pumpAndSettle();
    final page = tester.widget<SourceDetailPage>(find.byType(SourceDetailPage));
    expect(page.record.id, 'mangadex');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-local')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SourceDetailPage>(find.byType(SourceDetailPage)).record.id,
      'local',
    );
  });
}
