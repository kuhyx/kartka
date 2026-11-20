import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('a manga never opened shows its details while the chapter '
      'list loads; only the list is a wait (9f7cad2f)', (t) async {
    t.view.physicalSize = const Size(1200, 2400);
    addTearDown(t.view.resetPhysicalSize);
    final src = FakeSource('mangadex')..chaptersGate = Completer<void>();
    final h = Harness(sources: [src]);
    await h.pump(
      t,
      const SizedBox(),
      at: mangaRoute('mangadex', '/m/1'),
      settle: false, // The list bar animates until the gate opens.
    );
    await t.pump();
    await t.pump();
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final watch = find.byType(WaitWatch, skipOffstage: false);
    expect(watch, findsOneWidget);
    expect(t.widget<WaitWatch>(watch).operation, 'details.chapters');
    src.chaptersGate!.complete();
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('3 chapters'), findsOneWidget);
    expect(find.byType(WaitWatch, skipOffstage: false), findsNothing);
  });
}
