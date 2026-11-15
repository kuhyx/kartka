import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/ui/source_tile.dart';

import 'fit/browse_fit.dart';
import 'fit/fit_harness.dart';
import 'fit/library_fit.dart';
import 'fit/sources_fit.dart';
import 'fit/updates_fit.dart';

// build-mobile-app R7: every main tab fits one Pixel 6a screen inside the
// real shell (nav bar included); overflow goes to horizontal pages.
void main() {
  final screens = <String, Future<FitScreen> Function()>{
    'Library': libraryFit,
    'Updates': updatesFit,
    'Browse': browseFit,
    'Sources': sourcesFit,
  };
  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name fits one Pixel 6a screen', (tester) async {
      final s = await build();
      await pumpInShell(tester, s);
      expectFits(tester, s);
    });
  }
  for (final MapEntry(key: name, value: build) in {
    'Browse': browseFit,
    'Sources': sourcesFit,
  }.entries) {
    testWidgets('$name keeps search visible with the keyboard', (t) async {
      final s = await build();
      await pumpInShell(t, s, keyboard: 300);
      await t.tap(s.search!);
      await settle(t);
      expectSearchVisible(t, s);
    });
  }
  testWidgets('Library with 800 manga shows a page counter', (tester) async {
    final s = await libraryFit(count: 800);
    await pumpInShell(tester, s);
    expectPageCounter(tester);
  });

  testWidgets('a Browse tile gives the name its full width', (tester) async {
    final s = await browseFit();
    await pumpInShell(tester, s);
    final tile = find.byType(SourceTile).first;
    final name = find.descendant(of: tile, matching: find.text('Source 0'));
    // 8 dp tile padding each side.
    expect(
      tester.getSize(name).width,
      greaterThanOrEqualTo(tester.getSize(tile).width - 16 - 0.5),
    );
  });
}
