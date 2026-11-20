import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

void main() {
  testWidgets('the next page loads two screens before the end, so the '
      'footer spinner is rarely reached (89e1ec6e)', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <int>[];
    final c = PagedController<MangaSummary>((page) async {
      asked.add(page);
      return (
        items: [
          for (var i = 0; i < 25; i++)
            MangaSummary(sourceId: 's', url: '/$page/$i', title: 't$i'),
        ],
        hasNext: page < 5,
      );
    }, keyOf: (m) => m.url);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScope(
          deps: Harness(withCovers: false).deps,
          child: Scaffold(body: PagedMangaGrid(c)),
        ),
      ),
    );
    // The footer spinner never settles: pump the load and its post-frame.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    // Page 1 is five rows on a 600 px screen: about 860 px are left below,
    // more than the old 600 px trigger but under two screens, so page 2 is
    // fetched before the reader gets near the footer.
    expect(asked, containsAllInOrder([1, 2]));
  });

  testWidgets(
    'the next page loads as soon as the user is inside the last loaded '
    'page, one whole page ahead (bf7e99dc)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final asked = <int>[];
      final c = PagedController<MangaSummary>((page) async {
        asked.add(page);
        return (
          items: [
            for (var i = 0; i < 50; i++)
              MangaSummary(sourceId: 's', url: '/$page/$i', title: 't$i'),
          ],
          hasNext: page < 5,
        );
      }, keyOf: (m) => m.url);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScope(
            deps: Harness(withCovers: false).deps,
            child: Scaffold(body: PagedMangaGrid(c)),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(asked, [1, 2]);
      expect(asked, isNot(contains(3)));
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final pos = scrollable.position;
      final jumpTo = pos.maxScrollExtent / 2 + 10;
      pos.jumpTo(jumpTo);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(asked, contains(3));
    },
  );
}
