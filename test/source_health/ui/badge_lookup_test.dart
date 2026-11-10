import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

import '../fixtures.dart';
import 'harness.dart';

void main() {
  test('watch maps every record to its rank and verdict', () async {
    final SourceHealthLookup lookup = FeedSourceHealthLookup(
      FixtureSourceHealthFeed(fixtureJson('records.json')),
    );
    final map = await lookup.watch().first;
    expect(map, hasLength(6));
    expect(
      map['suwayomi:2499283573021220255'],
      const SourceHealthSummary(verdict: HealthVerdict.cut, rank: 3),
    );
    expect(
      map['suwayomi:7034581279101437511'],
      const SourceHealthSummary(verdict: HealthVerdict.pending),
    );
  });

  test('feed errors never break the Browse tab', () async {
    final feed = ControlledFeed();
    final lookup = FeedSourceHealthLookup(feed);
    final seen = <int>[];
    final sub = lookup.watch().listen((m) => seen.add(m.length));
    feed.controller
      ..addError(StateError('offline'))
      ..add(fixtureRecords());
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [6]);
  });

  testWidgets('buildBadge: a badge per known source, none otherwise', (
    tester,
  ) async {
    final lookup = FeedSourceHealthLookup(ControlledFeed());
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
    expect(lookup.buildBadge(ctx, 'x', null), isNull);
    final badge = lookup.buildBadge(
      ctx,
      'x',
      const SourceHealthSummary(verdict: HealthVerdict.keep, rank: 1),
    );
    expect(badge, isA<HealthBadge>());
  });

  testWidgets('badge shows rank + verdict with a spoken label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            HealthBadge(verdict: HealthVerdict.keep, rank: 1),
            HealthBadge(verdict: HealthVerdict.cut, rank: 7),
            HealthBadge(verdict: HealthVerdict.pending),
          ],
        ),
      ),
    );
    expect(find.text('#1'), findsOne);
    expect(find.text('#7'), findsOne);
    expect(find.byIcon(Icons.check_circle_outline), findsOne);
    expect(find.byIcon(Icons.cancel_outlined), findsOne);
    expect(find.byIcon(Icons.hourglass_empty), findsOne);
    expect(find.bySemanticsLabel('Source health: rank 1, keep'), findsOne);
    expect(find.bySemanticsLabel('Source health: pending'), findsOne);
    handle.dispose();
  });
}
