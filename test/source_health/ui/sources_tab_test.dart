import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/ranking.dart';
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

/// Opens [dropdown] and picks the item painted as [item] (a language code)
/// or spoken as it (a glyph item).
Future<void> choose(WidgetTester tester, Key dropdown, String item) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  final painted = find.text(item);
  final target = painted.evaluate().isEmpty ? spokenIcon(item) : painted;
  await tester.tap(target.last);
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
      '9/28',
      'p50 420 ms · p95 1.3 s',
      '35 %',
      '512/650 (79 %)',
      '97 % · 40',
      '1100 px',
      'q88',
      '#3',
      '0.81',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    for (final spoken in [
      'Uptime: accruing 9/28 probes',
      'Blocking: 35 % (Cloudflare challenge, 429 Too Many Requests)',
      'Chapters: 97 % over 40 titles',
      'Available as: native · JS plugin · Suwayomi',
      'Source health: pending',
      'Down too often: answered 22 of 28',
      'Catalogue too small: has 90 of 650',
      'Subset of MangaDex (93 %)',
    ]) {
      expect(spokenContaining(spoken), findsWidgets, reason: spoken);
    }
    expect(find.text('MangaDex (93 %)'), findsOne);
    expect(find.text('2026-10-24 12:00 UTC'), findsOne);
    expect(spokenContaining('older than 8 days'), findsNothing);
  });

  testWidgets('warns when results are stale', (tester) async {
    await pumpTab(tester, now: DateTime.utc(2026, 11, 10));
    expect(spokenContaining('older than 8 days'), findsOne);
  });

  testWidgets('every sort has a glyph; sorts best first, and reverses', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.byKey(const Key('sort')));
    await tester.pumpAndSettle();
    for (final s in HealthSort.values) {
      expect(spokenIcon(s.label), findsWidgets, reason: s.label);
    }
    expect(find.text('p95'), findsWidgets);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
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
    expect(spokenIcon('No match'), findsOne);
    await choose(tester, const Key('lang'), 'All languages');
    await choose(tester, const Key('origin'), 'All origins');
    await tester.tap(find.byKey(const Key('verdict-cut')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester, _ids), hasLength(6));
  });

  testWidgets('a card opens its detail page; subset links to the other', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.text('MangaDex (93 %)'));
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

  testWidgets('keyboard only: Tab reaches a card, Enter opens it', (
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
