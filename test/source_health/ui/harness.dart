import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// [child] inside the app's dark theme.
Widget host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(body: child),
);

/// The [StatusPill]s spoken as [label].
Finder pill(String label) =>
    find.byWidgetPredicate((w) => w is StatusPill && w.semanticLabel == label);

/// A tall test surface so every card of the list is built.
void tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A feed the test drives by hand.
class ControlledFeed implements SourceHealthFeed {
  /// Events pushed here reach every watcher.
  final controller = StreamController<List<SourceHealthRecord>>.broadcast();

  @override
  Stream<List<SourceHealthRecord>> watch() => controller.stream;

  /// Meta events pushed here reach every watcher.
  final meta = StreamController<SourceHealthMeta?>.broadcast();

  @override
  Stream<SourceHealthMeta?> watchMeta() => meta.stream;
}

/// Top-left of the tile for source [id].
Offset cardPos(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('source-$id')));

/// Source ids of the shown tiles, row by row, left to right.
List<String> cardOrder(WidgetTester tester, List<String> ids) {
  final shown =
      [
        for (final id in ids)
          if (find.byKey(ValueKey('source-$id')).evaluate().isNotEmpty) id,
      ]..sort((a, b) {
        final pa = cardPos(tester, a);
        final pb = cardPos(tester, b);
        return pa.dy == pb.dy ? pa.dx.compareTo(pb.dx) : pa.dy.compareTo(pb.dy);
      });
  return shown;
}

/// Opens the Filters sheet.
Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-filters')));
  await tester.pumpAndSettle();
}

/// Closes the open bottom sheet by tapping its barrier.
Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

/// Opens the long-press sheet (the full card) of source [id].
Future<void> openCard(WidgetTester tester, String id) async {
  await tester.longPress(find.byKey(ValueKey('source-$id')));
  await tester.pumpAndSettle();
}
