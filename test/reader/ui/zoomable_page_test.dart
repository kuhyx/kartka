import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/zoomable_page.dart';

void main() {
  Future<({List<Offset> taps, List<bool> zooms})> pump(
    WidgetTester tester,
  ) async {
    final taps = <Offset>[];
    final zooms = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ZoomablePage(
          onTap: taps.add,
          onZoomChanged: zooms.add,
          child: const SizedBox.expand(child: ColoredBox(color: Colors.red)),
        ),
      ),
    );
    return (taps: taps, zooms: zooms);
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  testWidgets('double tap zooms in at the tap and out again', (tester) async {
    final log = await pump(tester);
    await doubleTap(tester, const Offset(100, 100));
    expect(scaleOf(tester), greaterThan(1));
    expect(log.zooms, [true]);
    await doubleTap(tester, const Offset(100, 100));
    expect(scaleOf(tester), 1);
    expect(log.zooms, [true, false]);
    expect(log.taps, isEmpty);
  });

  testWidgets('single tap reports the position', (tester) async {
    final log = await pump(tester);
    await tester.tapAt(const Offset(30, 40));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    expect(log.taps, [const Offset(30, 40)]);
  });

  testWidgets('pinch that ends unzoomed reports nothing', (tester) async {
    final log = await pump(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.onInteractionEnd!(ScaleEndDetails());
    expect(log.zooms, isEmpty);
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    viewer.onInteractionEnd!(ScaleEndDetails());
    expect(log.zooms, [true]);
  });
}
