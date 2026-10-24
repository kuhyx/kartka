import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

import '../browser_engine_flag_test.dart' show allManga;
import '../fixtures.dart';
import 'harness.dart';

const chipText = 'Needs browser engine';

void main() {
  testWidgets('compact badge shows the chip only when flagged', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            HealthBadge(
              verdict: HealthVerdict.keep,
              rank: 2,
              needsBrowserEngine: true,
            ),
            HealthBadge(verdict: HealthVerdict.keep, rank: 1),
          ],
        ),
      ),
    );
    expect(find.text(chipText), findsOne);
    expect(find.text('#2 Keep'), findsOne);
    expect(find.text('#1 Keep'), findsOne);
  });

  testWidgets('the chip is a warning-coloured pill with a spoken label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const BrowserEngineChip()));
    expect(find.bySemanticsLabel('Warning: needs a browser engine'), findsOne);
    final pill = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(DecoratedBox),
      ),
    );
    final ctx = tester.element(find.byType(StatusPill));
    expect((pill.decoration as BoxDecoration).color, statusColors(ctx).warning);
    handle.dispose();
  });

  testWidgets('lookup badge for a flagged source includes the chip', (
    tester,
  ) async {
    final lookup = FeedSourceHealthLookup(FixtureSourceHealthFeed(const []));
    late BuildContext ctx;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final badge = lookup.buildBadge(
      ctx,
      'x',
      const SourceHealthSummary(
        verdict: HealthVerdict.keep,
        rank: 1,
        needsBrowserEngine: true,
      ),
    )!;
    await tester.pumpWidget(host(badge));
    expect(find.text(chipText), findsOne);
  });

  testWidgets('Sources row shows the chip; unflagged rows do not', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      host(
        ListView(
          children: [
            SourceCard(record: allManga, onOpen: (_) {}, nameOf: (_) => null),
            SourceCard(
              record: fixtureRecord('mangadex'),
              onOpen: (_) {},
              nameOf: (_) => null,
            ),
          ],
        ),
      ),
    );
    expect(find.text(chipText), findsOne);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('detail page shows the chip and a one-line explanation', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      host(
        SourceDetailPage(
          record: allManga,
          all: const [allManga],
          now: DateTime.utc(2026, 10, 25),
        ),
      ),
    );
    expect(find.text(chipText), findsOne);
    expect(find.textContaining('needs a browser engine'), findsWidgets);
    expect(find.textContaining('flagged, not cut'), findsOne);
  });

  testWidgets('detail page of an unflagged source has no chip', (tester) async {
    tallSurface(tester);
    final r = fixtureRecord('mangadex');
    await tester.pumpWidget(
      host(
        SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 10, 25)),
      ),
    );
    expect(find.text(chipText), findsNothing);
    expect(find.textContaining('flagged, not cut'), findsNothing);
  });
}
