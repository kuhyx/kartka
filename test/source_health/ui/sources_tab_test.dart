import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/ui/filters_sheet.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../../helpers/spoken_icon.dart';
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

/// Picks [item] from [dropdown]: painted (a language code) or spoken.
Future<void> choose(WidgetTester tester, Key dropdown, String item) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  final painted = find.text(item);
  final target = painted.evaluate().isEmpty ? spokenIcon(item) : painted;
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ranks every source in a two-column grid of tiles', (
    tester,
  ) async {
    await pumpTab(tester);
    expect(cardOrder(tester, _ids), [
      'mangadex',
      'local',
      'suwayomi:2499283573021220255',
      'suwayomi:1111',
      'plugin:comick',
      'suwayomi:7034581279101437511',
    ]);
    expect(
      cardPos(tester, 'local').dx,
      greaterThan(cardPos(tester, 'mangadex').dx),
    );
    for (final text in ['#3', '0.81', 'en']) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    for (final spoken in [
      'Source health: rank 3, cut',
      'Source health: pending',
      'Suwayomi · en',
    ]) {
      expect(spokenContaining(spoken), findsWidgets, reason: spoken);
    }
    expect(spokenIcon('Failing checks'), findsWidgets);
  });

  testWidgets('long-press shows every metric and reason of the source', (
    tester,
  ) async {
    await pumpTab(tester);
    await openCard(tester, 'suwayomi:2499283573021220255');
    for (final text in [
      '96 % (27/28)',
      'p50 420 ms · p95 1.3 s',
      '512/650 (79 %)',
      '97 % · 40',
      '1100 px',
      'q88',
      'MangaDex (93 %)',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    for (final spoken in [
      'Chapters: 97 % over 40 titles',
      'Available as: native · JS plugin · Suwayomi',
      'Subset of MangaDex (93 %)',
    ]) {
      expect(spokenContaining(spoken), findsWidgets, reason: spoken);
    }
    await closeSheet(tester);
    await openCard(tester, 'suwayomi:7034581279101437511');
    expect(find.text('9/28'), findsOne);
    expect(spokenContaining('Uptime: accruing 9/28 probes'), findsOne);
    await closeSheet(tester);
    await openCard(tester, 'plugin:comick');
    expect(find.text('35 %'), findsWidgets);
    for (final spoken in [
      'Blocking: 35 % (Cloudflare challenge, 429 Too Many Requests)',
      'Down too often: answered 22 of 28',
    ]) {
      expect(spokenContaining(spoken), findsOne, reason: spoken);
    }
    await closeSheet(tester);
    await openCard(tester, 'suwayomi:1111');
    expect(spokenContaining('Catalogue too small: has 90 of 650'), findsOne);
  });

  testWidgets('shows when it was evaluated; Stale pill when old', (
    tester,
  ) async {
    await pumpTab(tester);
    expect(spokenIcon('Last evaluated'), findsOne);
    expect(find.text('2026-10-24 12:00 UTC'), findsOne);
    expect(spokenContaining('Stale: results'), findsNothing);
    await openFilters(tester);
    expect(spokenContaining('older than 8 days'), findsNothing);
  });

  testWidgets('warns when results are stale', (tester) async {
    await pumpTab(tester, now: DateTime.utc(2026, 11, 10));
    expect(spokenContaining('Stale: results'), findsOne);
    await openFilters(tester);
    expect(
      find.descendant(
        of: find.byType(FiltersSheet),
        matching: spokenContaining('older than 8 days'),
      ),
      findsOne,
    );
  });

  testWidgets('the Filters badge counts what is not default', (tester) async {
    await pumpTab(tester);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('0')),
      findsNothing,
    );
    await openFilters(tester);
    await tester.tap(find.byKey(const Key('verdict-cut')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reverse')));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    expect(find.text('2'), findsOne);
  });

  testWidgets('sorts by any metric, best first, and reverses', (tester) async {
    await pumpTab(tester);
    await openFilters(tester);
    await choose(tester, const Key('sort'), 'Coverage');
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
    await openFilters(tester);
    await tester.tap(find.byKey(const Key('verdict-cut')));
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
    await closeSheet(tester);
    expect(spokenIcon('No match'), findsOne);
    await openFilters(tester);
    await choose(tester, const Key('lang'), 'All languages');
    await choose(tester, const Key('origin'), 'All origins');
    await tester.tap(find.byKey(const Key('verdict-cut')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(6));
  });

  testWidgets('a tile opens its detail page; subset links to the other', (
    tester,
  ) async {
    await pumpTab(tester);
    await openCard(tester, 'suwayomi:2499283573021220255');
    await tester.tap(find.text('MangaDex (93 %)'));
    await tester.pumpAndSettle();
    final page = tester.widget<SourceDetailPage>(find.byType(SourceDetailPage));
    expect(page.record.id, 'mangadex');
    expect(find.text('MangaDex (93 %)'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-local')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SourceDetailPage>(find.byType(SourceDetailPage)).record.id,
      'local',
    );
  });

  testWidgets('the card in the long-press sheet opens the detail page', (
    tester,
  ) async {
    await pumpTab(tester);
    await openCard(tester, 'local');
    await tester.tap(find.byKey(const ValueKey('source-card-local')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SourceDetailPage>(find.byType(SourceDetailPage)).record.id,
      'local',
    );
  });

  testWidgets('keyboard only: Tab reaches a tile, Enter opens it', (
    tester,
  ) async {
    await pumpTab(tester);
    final card = find.byKey(const ValueKey('source-local'));
    bool focusedInCard() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      return ctx != null &&
          find
              .ancestor(
                of: find.byElementPredicate((e) => e == ctx),
                matching: card,
              )
              .evaluate()
              .isNotEmpty;
    }

    for (var i = 0; i < 60 && !focusedInCard(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedInCard(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SourceDetailPage>(find.byType(SourceDetailPage)).record.id,
      'local',
    );
  });
}
