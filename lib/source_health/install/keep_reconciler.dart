import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/keep_plan.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/install/source_probe.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// Installs every `keep` source that is not installed yet, without asking,
/// once per published evaluation, then tests each one it installed.
///
/// Installs only, never uninstalls (the ports cannot). A source carrying
/// `pkg` installs on the Suwayomi server (one install per package, however
/// many sources it serves), else one carrying `plugin` through the plugin
/// manager. "Installed" is read from each side's lister, never from the
/// live source list. A side that cannot be read is skipped and the publish
/// is not remembered, so the next start tries again. Failures are flagged
/// ([flagOf]) and logged as `sources.autoinstall`, URLs stripped.
class KeepReconciler extends ChangeNotifier {
  /// Creates the reconciler; it does nothing until [start] or [reconcile].
  new({
    required this.kv,
    required this.probe,
    SuwayomiExtensionInstaller? Function()? suwayomi,
    PluginRepoInstaller? Function()? plugins,
    this.diagnostics,
    this.now = DateTime.now,
    this.concurrency = 2,
  }) : _suwayomi = suwayomi ?? _none,
       _plugins = plugins ?? _none;

  static T? _none<T>() => null;

  /// Device-local storage of [state].
  final KeyValueStore kv;

  /// Tests a freshly installed source.
  final SourceProbe probe;

  /// Where failures are logged.
  final DiagnosticsLog? diagnostics;

  /// Current time, for the log.
  final DateTime Function() now;

  /// Installs in flight at most.
  final int concurrency;

  final SuwayomiExtensionInstaller? Function() _suwayomi;
  final PluginRepoInstaller? Function() _plugins;
  final _subs = <StreamSubscription<Object?>>[];
  List<SourceHealthRecord>? _records;
  SourceHealthMeta? _meta;
  var _metaSeen = false;
  Future<void>? _running;
  var _again = false;

  /// What the last run did (empty before [load]).
  AutoInstallState state = const AutoInstallState();

  /// The quiet one-line status of the last run; null when nothing to say.
  String? get status => state.status;

  /// The flag shown for source [id] after a failed install or test.
  String? flagOf(String id) => state.failures[id]?.flag;

  /// Whether the publish [id] still needs a reconcile.
  bool needsRun(String id) => id != state.publishId;

  /// Reads the stored state.
  Future<void> load() async {
    state = await AutoInstallState.load(kv);
    notifyListeners();
  }

  /// Loads the state, then reconciles every new publish of [feed] (the
  /// scored feed: verdicts under the active profile).
  Future<void> start(SourceHealthFeed feed) async {
    await load();
    _subs
      ..add(
        feed.watch().listen((r) {
          _records = r;
          _kick();
        }, onError: (Object _) {}),
      )
      ..add(
        feed.watchMeta().listen(
          _sawMeta,
          onError: (Object _) => _sawMeta(null),
        ),
      );
  }

  void _sawMeta(SourceHealthMeta? meta) {
    _meta = meta;
    _metaSeen = true;
    _kick();
  }

  void _kick() {
    final records = _records;
    if (records == null || !_metaSeen) return;
    final id = publishIdOf(records, _meta);
    if (id == null || !needsRun(id)) return;
    if (_running != null) {
      _again = true;
      return;
    }
    _running = reconcile(records, id).whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        _kick();
      }
    });
  }

  /// Installs and tests the keep sources of [records] that are missing,
  /// re-tests the ones flagged last time, and remembers [publishId] when
  /// both sides could be read. A publish already reconciled is a no-op.
  Future<void> reconcile(
    List<SourceHealthRecord> records,
    String publishId,
  ) async {
    if (!needsRun(publishId)) return;
    final keep = [
      for (final r in records)
        if (r.verdict == HealthVerdict.keep) r,
    ];
    final suwayomi = _suwayomi();
    final plugins = _plugins();
    final packages = await installedOf<InstalledExtensionLister>(
      suwayomi,
      (l) => l.installedPackages(),
    );
    final pluginIds = await installedOf<InstalledPluginLister>(
      plugins,
      (l) => l.installedPluginIds(),
    );
    final jobs = planKeepInstalls(keep, packages: packages, plugins: pluginIds);
    final installed = <String>[];
    final failures = <String, AutoInstallFailure>{};
    void fail(String id, AutoInstallStage stage, String reason) {
      final redacted = stripUrls(reason);
      failures[id] = AutoInstallFailure(stage, redacted);
      unawaited(
        diagnostics?.append(
          DiagnosticEntry.failure(
            at: now(),
            kind: 'sources.autoinstall',
            error: '${stage.name} failed: $redacted',
            sourceId: id,
          ),
        ),
      );
    }

    Future<void> test(String id) async {
      if (await probe(id) case final why?) {
        fail(id, AutoInstallStage.test, why);
      }
    }

    await runPooled(jobs, concurrency, (group) async {
      final first = group.first;
      try {
        if (first.pkg case final pkg?) {
          await suwayomi!.installExtension(pkg);
        } else {
          final ref = first.plugin!;
          await plugins!.installPlugin(repo: ref.repo, id: ref.id);
        }
      } on Object catch (e) {
        for (final r in group) {
          fail(r.id, AutoInstallStage.install, '$e');
        }
        return;
      }
      for (final r in group) {
        installed.add(r.id);
        await test(r.id);
      }
    });
    final queued = {for (final g in jobs) ...g.map((r) => r.id)};
    for (final r in keep) {
      final was = state.failures[r.id];
      if (was?.stage == AutoInstallStage.test && !queued.contains(r.id)) {
        await test(r.id);
      }
    }
    final complete =
        (suwayomi == null || packages != null) &&
        (plugins == null || pluginIds != null);
    state = AutoInstallState(
      publishId: complete ? publishId : state.publishId,
      installed: installed,
      failures: failures,
    );
    await state.save(kv);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
