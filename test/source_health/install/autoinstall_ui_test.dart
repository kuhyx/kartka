import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../ui/harness.dart';
import 'autoinstall_fakes.dart';

void main() {
  testWidgets('a source whose test failed shows the flag under Open, and the '
      'tab shows the status line', (tester) async {
    tallSurface(tester);
    final rig = ReconcileRig()..probeFailures['suwayomi:1'] = 'no titles';
    final ids = StreamController<Set<String>>.broadcast(sync: true);
    final installs = SourceInstalls(
      sourceIds: ids.stream,
      open: (_, _) {},
      suwayomi: () => rig.suwayomi,
      autoInstall: rig.reconciler,
    );
    addTearDown(installs.dispose);
    final feed = ControlledFeed();
    final records = [
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
      keepRecord('suwayomi:2', pkg: 'pkg.b', rank: 2),
    ];
    await tester.pumpWidget(
      host(
        SourcesTab(feed: feed, installs: installs, autoInstall: rig.reconciler),
      ),
    );
    feed.controller.add(records);
    feed.meta.add(null);
    ids.add({'suwayomi:1', 'suwayomi:2'});
    await tester.pump();
    expect(find.byKey(const Key('autoinstall-status')), findsNothing);
    expect(find.byKey(const Key('migrate-better')), findsNothing);

    await tester.runAsync(() => rig.reconciler.reconcile(records, 'W1'));
    await tester.pump();
    expect(find.text('Installed 2 sources, 1 failed its test'), findsOne);
    expect(find.byKey(const ValueKey('open-suwayomi:1')), findsOne);
    expect(find.text('Installed — test failed: no titles'), findsOne);
    expect(
      find.byKey(const ValueKey('autoinstall-flag-suwayomi:2')),
      findsNothing,
    );
  });

  testWidgets('Migrate to better sources calls back with the context', (
    tester,
  ) async {
    tallSurface(tester);
    final feed = ControlledFeed();
    BuildContext? opened;
    await tester.pumpWidget(
      host(SourcesTab(feed: feed, onMigrate: (context) => opened = context)),
    );
    feed.controller.add([keepRecord('suwayomi:1')]);
    feed.meta.add(null);
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-better')));
    expect(opened, isNotNull);
  });
}
