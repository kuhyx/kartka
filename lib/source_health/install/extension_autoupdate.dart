import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/keep_plan.dart';

/// What one auto-update run did.
typedef AutoUpdateResult = ({List<String> updated, List<String> failed});

/// Updates every installed Suwayomi extension the store has a newer build
/// of, once per app start and at most once per [interval] (device-local
/// stamp in [kv]). Beside `KeepReconciler`'s installs: nothing else updates
/// extensions, and a stale one breaks (Atsumaru 1.6.25's search answered
/// HTTP 400 while popular still worked).
///
/// Off the UI's critical path (started unawaited from the first screen).
/// A list that cannot be read leaves the stamp unset, so the next start
/// retries; a failed update does not. The headless agent instance
/// ([isAgent]) never runs: it reads the same shared server.
class ExtensionAutoUpdater {
  /// Creates the updater; it does nothing until [run].
  new({
    required this.kv,
    required this._updater,
    required this.isAgent,
    this.diagnostics,
    this.now = DateTime.now,
    this.concurrency = 1,
    this.interval = const Duration(hours: 24),
  });

  /// Device-local kv key of the last run's UTC ISO-8601 time.
  static const stampKey = 'sourceHealth.autoUpdate.lastRun';

  /// Device-local storage of the stamp.
  final KeyValueStore kv;

  /// Whether this is the headless agent instance.
  final Future<bool> Function() isAgent;

  /// Where the summary goes (`sources.autoupdate`, counts and names only).
  final DiagnosticsLog? diagnostics;

  /// Current time.
  final DateTime Function() now;

  /// Updates in flight at most.
  final int concurrency;

  /// Shortest time between two runs.
  final Duration interval;

  final SuwayomiExtensionUpdater? Function() _updater;
  var _ran = false;

  /// Updates the outdated extensions; null when skipped (already ran here,
  /// ran within [interval], agent instance, no Suwayomi part, or the list
  /// could not be read).
  Future<AutoUpdateResult?> run() async {
    if (_ran) return null;
    _ran = true;
    final updater = _updater();
    if (updater == null || await isAgent()) return null;
    final at = now().toUtc();
    final last = DateTime.tryParse(await kv.get(stampKey) ?? '');
    if (last != null && at.difference(last) < interval) return null;
    final List<String> outdated;
    try {
      outdated = await updater.outdatedPackages();
    } on Object {
      return null;
    }
    await kv.set(stampKey, at.toIso8601String());
    final updated = <String>[];
    final failed = <String>[];
    await runPooled(outdated, concurrency, (pkg) async {
      try {
        await updater.updateExtension(pkg);
        updated.add(pkg);
      } on Object {
        failed.add(pkg);
      }
    });
    updated.sort();
    failed.sort();
    if (outdated.isNotEmpty) {
      await diagnostics?.append(
        DiagnosticEntry(
          at: at,
          kind: autoUpdateKind,
          error: [
            'updated ${updated.length} [${updated.join(', ')}]',
            if (failed.isNotEmpty)
              '$autoUpdateFailed ${failed.length} [${failed.join(', ')}]',
          ].join(', '),
        ),
      );
    }
    return (updated: updated, failed: failed);
  }
}
