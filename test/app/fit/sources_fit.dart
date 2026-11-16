import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/ui/source_tile.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';
import 'package:material_ui/material_ui.dart';

import '../../source_health/fixtures.dart';
import 'fit_harness.dart';

/// 40 health records (the fixture rows, re-id'd): more than one page.
Future<FitScreen> sourcesFit() async {
  final base = fixtureMaps();
  final json = [
    for (var i = 0; i < 40; i++)
      {
        ...base[i % base.length],
        'id': 'fit:$i',
        'name': 'Source number $i',
        'rank': i + 1,
      },
  ];
  return FitScreen(
    tab: KartkaTab.sources,
    screen: (_) => SourcesTab(
      feed: FixtureSourceHealthFeed(json),
      clock: () => DateTime.utc(2026, 10, 25),
    ),
    tiles: find.byType(SourceTile),
    search: find.byKey(const Key('search')),
  );
}
