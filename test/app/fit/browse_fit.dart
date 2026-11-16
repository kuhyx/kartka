import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/browse/ui/source_tile.dart';
import 'package:material_ui/material_ui.dart';

import '../../browse/fakes.dart';
import '../../browse/ui/harness.dart';
import 'fit_harness.dart';

/// Browse with 40 sources in one language and origin: more than one page.
Future<FitScreen> browseFit() async {
  final h = Harness(
    sources: [
      for (var i = 0; i < 40; i++) FakeSource('src$i', name: 'Source $i'),
    ],
  );
  return FitScreen(
    tab: KartkaTab.browse,
    screen: (_) => BrowseScope(deps: h.deps, child: const BrowseTab()),
    tiles: find.byType(SourceTile),
    search: find.byType(TextField),
  );
}
