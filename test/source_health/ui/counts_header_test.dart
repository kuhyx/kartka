import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/ui/skipped_page.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../../helpers/spoken_icon.dart';
import '../fixtures.dart';
import 'harness.dart';

/// The spoken counts line (the painted form is glyphs and numbers).
String counts(WidgetTester tester) =>
    tester.widget<SpokenLabel>(find.byKey(const Key('counts'))).semanticLabel;

void main() {
  testWidgets('meta node fills the header; tap lists skipped groups', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      host(
        SourcesTab(
          feed: FixtureSourceHealthFeed(
            fixtureJson('records.json'),
            meta: fixtureJson('meta.json'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      counts(tester),
      '585 tested of 590 candidates · 120 keep · 400 cut · 65 pending · '
      'showing 6',
    );
    for (final n in ['585/590', '120', '400', '65', '6']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
    await tester.tap(find.byKey(const Key('counts')));
    await tester.pumpAndSettle();
    expect(find.byType(SkippedPage), findsOne);
    expect(find.text('keiyoushi · nsfw · 3'), findsOne);
    expect(find.text('mangayomi · duplicate of a native source · 2'), findsOne);
    expect(find.text('2026-10-24T12-00-00Z · 2026-10-24 12:00 UTC'), findsOne);
    expect(find.text('Hentai B'), findsNothing);
    await tester.tap(find.text('keiyoushi · nsfw · 3'));
    await tester.pumpAndSettle();
    expect(find.text('Hentai B'), findsOne);
  });

  testWidgets('no meta node: counts from records, no tap target', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      host(
        SourcesTab(feed: FixtureSourceHealthFeed(fixtureJson('records.json'))),
      ),
    );
    await tester.pump();
    expect(
      counts(tester),
      '6 tested · candidates unknown · 2 keep · 3 cut · 1 pending · showing 6',
    );
    await tester.tap(find.byKey(const Key('counts')));
    await tester.pumpAndSettle();
    expect(find.byType(SkippedPage), findsNothing);
  });

  testWidgets('meta read errors and partial meta fall back per field', (
    tester,
  ) async {
    tallSurface(tester);
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.add(fixtureRecords());
    await tester.pump();
    feed.meta.addError(StateError('denied'));
    await tester.pump();
    expect(counts(tester), startsWith('6 tested · candidates unknown'));
    feed.meta.add(const SourceHealthMeta(tested: 9));
    await tester.pump();
    await tester.pump();
    expect(
      counts(tester),
      '9 tested · candidates unknown · 2 keep · 3 cut · 1 pending · showing 6',
    );
  });

  testWidgets('skipped page with nothing skipped says so', (tester) async {
    await tester.pumpWidget(
      host(
        const SkippedPage(
          meta: SourceHealthMeta(
            skipped: [SkippedGroup(index: 'x', reason: 'odd', count: 1)],
          ),
        ),
      ),
    );
    await tester.tap(find.text('x · odd · 1'));
    await tester.pumpAndSettle();
    expect(spokenIcon('No names'), findsOne);
    await tester.pumpWidget(host(const SkippedPage(meta: SourceHealthMeta())));
    expect(spokenIcon('Nothing was skipped'), findsOne);
  });
}
