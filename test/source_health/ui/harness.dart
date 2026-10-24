import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// [child] inside the app's dark theme.
Widget host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(body: child),
);

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
}

/// Top edge of the card for source [id].
double cardTop(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('source-$id'))).dy;

/// Source ids of the shown cards, top to bottom.
List<String> cardOrder(WidgetTester tester, List<String> ids) {
  final shown = [
    for (final id in ids)
      if (find.byKey(ValueKey('source-$id')).evaluate().isNotEmpty) id,
  ]..sort((a, b) => cardTop(tester, a).compareTo(cardTop(tester, b)));
  return shown;
}
