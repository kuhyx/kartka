import 'dart:async';

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/quality_metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// A `keep` record installable through Suwayomi [pkg] or plugin [plugin].
SourceHealthRecord keepRecord(
  String id, {
  String? pkg,
  String? plugin,
  int rank = 1,
  HealthVerdict verdict = HealthVerdict.keep,
}) => SourceHealthRecord(
  id: id,
  name: id,
  verdict: verdict,
  rank: rank,
  pkg: pkg,
  plugin: plugin == null
      ? null
      : PluginInstallRef(repo: 'https://repo.test/index.json', id: plugin),
);

/// A Suwayomi side that installs into [installed]; logs every call.
class FakeSuwayomi
    implements SuwayomiExtensionInstaller, InstalledExtensionLister {
  new([Set<String>? installed]) : installed = installed ?? {};

  /// Installed packages.
  final Set<String> installed;

  /// Every call, in order (`list`, `install:<pkg>`).
  final calls = <String>[];

  /// Thrown by [installedPackages] when set.
  Error? listError;

  /// Packages whose install throws.
  final failing = <String, Error>{};

  /// Installs running right now, and the most seen at once.
  int inFlight = 0;

  /// The most installs seen running at once.
  int maxInFlight = 0;

  @override
  Future<Set<String>> installedPackages() async {
    calls.add('list');
    if (listError case final e?) throw e;
    return {...installed};
  }

  @override
  Future<void> installExtension(String pkg) async {
    calls.add('install:$pkg');
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(Duration.zero);
    inFlight--;
    if (failing[pkg] case final e?) throw e;
    installed.add(pkg);
  }
}

/// A plugin side that installs into [installed]; logs every call.
class FakePlugins implements PluginRepoInstaller, InstalledPluginLister {
  /// Installed plugin ids.
  final installed = <String>{};

  /// Every call, in order (`list`, `install:<id>`).
  final calls = <String>[];

  /// Thrown by [installedPluginIds] when set.
  Error? listError;

  @override
  Future<Set<String>> installedPluginIds() async {
    calls.add('list');
    if (listError case final e?) throw e;
    return {...installed};
  }

  @override
  Future<void> installPlugin({required String repo, required String id}) async {
    calls.add('install:$id');
    installed.add(id);
  }
}

/// Installs a Suwayomi extension but cannot list them (an older port).
class BlindSuwayomi implements SuwayomiExtensionInstaller {
  /// Packages installed.
  final calls = <String>[];

  @override
  Future<void> installExtension(String pkg) async => calls.add(pkg);
}

/// One reconciler over fakes.
class ReconcileRig {
  new({
    FakeSuwayomi? suwayomi,
    this.plugins,
    this.blind,
    MemoryKeyValueStore? kv,
  }) : suwayomi = suwayomi ?? FakeSuwayomi(),
       kv = kv ?? MemoryKeyValueStore();

  /// The Suwayomi side.
  final FakeSuwayomi suwayomi;

  /// The plugin side; none registered when null.
  final FakePlugins? plugins;

  /// A Suwayomi side that cannot list (replaces [suwayomi] when set).
  final BlindSuwayomi? blind;

  /// Device-local storage.
  final MemoryKeyValueStore kv;

  /// Probe answers by source id (missing = passes).
  final probeFailures = <String, String>{};

  /// Every probed source id, in order.
  final probed = <String>[];

  /// The diagnostics log.
  final log = DiagnosticsLog(MemoryBlobStore());

  /// The reconciler under test.
  late final reconciler = KeepReconciler(
    kv: kv,
    probe: (id) async {
      probed.add(id);
      return probeFailures[id];
    },
    suwayomi: () => blind ?? suwayomi,
    plugins: () => plugins,
    diagnostics: log,
    now: () => DateTime.utc(2026, 10, 29),
  );
}
