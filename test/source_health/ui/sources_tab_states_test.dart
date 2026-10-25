import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../fixtures.dart';
import 'harness.dart';

void main() {
  testWidgets('loading, then data, then live updates', (tester) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    expect(find.byType(CircularProgressIndicator), findsOne);
    feed.controller.add(fixtureRecords());
    await tester.pump();
    expect(find.byKey(const ValueKey('source-mangadex')), findsOne);
    feed.controller.add([fixtureRecord('local')]);
    await tester.pump();
    expect(find.byKey(const ValueKey('source-mangadex')), findsNothing);
    expect(find.byKey(const ValueKey('source-local')), findsOne);
  });

  testWidgets('empty ranking explains where results come from', (tester) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.add(const []);
    await tester.pump();
    expect(find.text('No source health yet'), findsOne);
  });

  testWidgets('read errors are shown, not hidden', (tester) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.addError(StateError('offline'));
    await tester.pump();
    expect(find.text("Couldn't read source health"), findsOne);
    expect(find.textContaining('offline'), findsOne);
  });

  testWidgets('a read error never shows the token in its URL', (tester) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.addError(
      StateError('401 at https://x.firebaseio.com/kartka.json?auth=SECRET123'),
    );
    await tester.pump();
    expect(find.textContaining('SECRET123'), findsNothing);
    expect(
      find.textContaining('https://x.firebaseio.com/kartka.json'),
      findsOne,
    );
  });

  testWidgets('never evaluated counts as stale', (tester) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.add([
      for (final m in fixtureMaps())
        SourceHealthRecord.fromJson(m..remove('probedAt'))!,
    ]);
    await tester.pump();
    expect(find.text('Never evaluated'), findsOne);
    expect(find.textContaining('older than 8 days'), findsOne);
  });

  testWidgets('subset link to a source outside the ranking is disabled', (
    tester,
  ) async {
    final feed = ControlledFeed();
    await tester.pumpWidget(host(SourcesTab(feed: feed)));
    feed.controller.add([
      SourceHealthRecord.fromJson(const {
        'id': 'a',
        'subsetOf': {'sourceId': 'gone', 'overlap': 0.95},
        'cutReasons': ['subset'],
      })!,
    ]);
    await tester.pump();
    final link = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Subset of gone (95 %)'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(link.onPressed, isNull);
  });
}
