import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';

import '../ui/harness.dart';

/// Atsumaru's Suwayomi extension package (the one kuhy installs).
const atsumaruPkg = 'eu.kanade.tachiyomi.extension.en.atsumaru';

/// A Suwayomi record with [pkg].
SourceHealthRecord suwayomiRecord({
  String id = 'suwayomi:42',
  String? pkg = atsumaruPkg,
}) =>
    SourceHealthRecord(id: id, name: 'Atsumaru', origin: 'suwayomi', pkg: pkg);

/// What one test drives: the live source ids, opened routes and the log.
class InstallRig {
  /// Creates the rig; installers default to none registered.
  new({this.suwayomi, this.plugins});

  /// The registered Suwayomi installer, if any.
  final SuwayomiExtensionInstaller? suwayomi;

  /// The registered plugin installer, if any.
  final PluginRepoInstaller? plugins;

  /// Source ids the app lists (push to change them).
  final ids = StreamController<Set<String>>.broadcast(sync: true);

  /// Every source id Open navigated to.
  final opened = <String>[];

  /// The diagnostics log failures land in.
  final log = DiagnosticsLog(MemoryBlobStore());

  /// The controller under test.
  late final installs = SourceInstalls(
    sourceIds: ids.stream,
    open: (_, id) => opened.add(id),
    suwayomi: () => suwayomi,
    plugins: () => plugins,
    diagnostics: log,
    now: () => DateTime.utc(2026, 10, 25),
  );

  /// Every logged entry.
  Future<List<DiagnosticEntry>> entries() => log.entries();
}

/// The Sources tab showing [records] with [rig]'s actions.
Future<void> pumpTabWith(
  WidgetTester tester,
  InstallRig rig,
  List<SourceHealthRecord> records, {
  Set<String> installed = const {},
}) async {
  tallSurface(tester);
  final feed = ControlledFeed();
  await tester.pumpWidget(host(SourcesTab(feed: feed, installs: rig.installs)));
  feed.controller.add(records);
  feed.meta.add(null);
  rig.ids.add(installed);
  await tester.pump();
  await tester.pump();
}

/// [record]'s detail page with [rig]'s actions.
Future<void> pumpDetailWith(
  WidgetTester tester,
  InstallRig rig,
  SourceHealthRecord record,
) async {
  tallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: SourceDetailPage(
        record: record,
        all: [record],
        now: DateTime.utc(2026, 10, 25),
        installs: rig.installs,
      ),
    ),
  );
  rig.ids.add(const {});
  await tester.pump();
}

/// The Install button of [id].
Finder installOf(String id) => find.byKey(ValueKey('install-$id'));

/// The Open button of [id].
Finder openOf(String id) => find.byKey(ValueKey('open-$id'));

/// The in-flight (disabled) button of [id].
Finder installingOf(String id) => find.byKey(ValueKey('installing-$id'));
