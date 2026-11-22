import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes.dart';
import 'harness.dart';

const _tile = MangaSummary(sourceId: 'mangadex', url: '/m/1', title: 'T');

/// A hover that rests on a tile, or a press, starts its detail fetches
/// before the route opens (9f7cad2f); a mouse only crossing it does not.
void main() {
  late FakeSource src;
  late BrowseDeps deps;

  Future<void> pump(WidgetTester tester) async {
    src = FakeSource('mangadex');
    deps = Harness(sources: [src], withCovers: false).deps;
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScope(
          deps: deps,
          child: const Scaffold(
            body: SizedBox(width: 150, height: 250, child: MangaTile(_tile)),
          ),
        ),
      ),
    );
  }

  testWidgets('a resting hover warms the tile, a passing one does not', (
    tester,
  ) async {
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(MangaTile)));
    await tester.pump(const Duration(milliseconds: 50));
    await mouse.moveTo(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(src.calls, isEmpty);

    await mouse.moveTo(tester.getCenter(find.byType(MangaTile)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(src.calls, ['details:/m/1', 'chapters:/m/1']);
    expect(deps.prefetch.take(_tile.key)?.tile, _tile);
  });

  testWidgets('a press warms the tile at once', (tester) async {
    await pump(tester);
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(MangaTile)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(src.calls, ['details:/m/1', 'chapters:/m/1']);
    await finger.cancel();
  });
}
