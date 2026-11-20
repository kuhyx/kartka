import 'dart:async';

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/migration/dedupe/dupe_merger.dart';
import 'package:kartka/migration/dedupe/dupe_rule.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_backup.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/platform/key_value_store.dart';

export 'package:kartka/migration/dedupe/dupe_facts.dart';

/// Diagnostics kind of the line a run that merged something logs (it stays
/// on the device: `deviceOnlyKinds`).
const dedupeKind = 'library.dedupe';

/// Device-local key of the last run's instant (the start-up gate).
const dedupeLastRunKey = 'library.dedupe.lastRun';

/// The start-up run is skipped when a run finished less than this ago.
const dedupeEvery = Duration(hours: 6);

/// Merges library entries that are literally the same series onto the one
/// on the best source (DOCS-spec "Duplicate merging"; rules in
/// `dupe_rule.dart`, the merge in `dupe_merger.dart`).
///
/// Judges only what this device stored (never fetches). Without a ranking
/// or with no installed source it does nothing and keeps its gate open:
/// a winner picked blind could delete the better entry. One backup
/// (`exportBackup`) precedes the first merge of a run; a failed backup
/// merges nothing.
class LibraryDeduper implements LibraryStartTask {
  /// Creates the deduper; every input is read lazily (the registry is
  /// complete only after every feature factory ran).
  new({
    required this.deps,
    required this.facts,
    required this.health,
    required this.installed,
    required this.local,
    required this.updater,
    this.log,
    this.clock = utcNow,
  });

  /// Repositories and the backup store.
  final MigrationDeps Function() deps;

  /// Stored details and chapters per entry (browse).
  final DupeFactsLookup? Function() facts;

  /// The evaluator's summaries by source id; null when unavailable.
  final Future<Map<String, SourceHealthSummary>?> Function() health;

  /// Ids of the installed sources.
  final Future<Set<String>> Function() installed;

  /// Where [dedupeLastRunKey] lives (device-local).
  final KeyValueStore local;

  /// The shared "update all" run; each finished run triggers [run].
  final LibraryUpdater? Function() updater;

  /// Where a run that merged something logs its counts.
  final DiagnosticsLog? log;

  /// Clock of the start-up gate and the log line.
  final DateTime Function() clock;

  Future<int>? _run;
  bool _started = false;

  /// Completes when no run is in flight.
  Future<void> get idle => _run ?? Future.value();

  /// Once per launch (the library's first load): follows [updater], then
  /// runs unless a run finished within [dedupeEvery].
  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _follow();
    final last = DateTime.tryParse(await local.get(dedupeLastRunKey) ?? '');
    if (last != null && clock().difference(last) < dedupeEvery) return;
    await run();
  }

  void _follow() {
    final u = updater();
    if (u == null) return;
    var running = u.progress != null;
    u.addListener(() {
      final now = u.progress != null;
      if (running && !now) unawaited(run());
      running = now;
    });
  }

  /// Merges every duplicate; returns how many entries were merged away. A
  /// call while a run is in flight joins it.
  Future<int> run() => _run ??= _runOnce();

  Future<int> _runOnce() async {
    try {
      final lookup = facts();
      final ranks = await health();
      final ids = await installed();
      if (lookup == null || ranks == null || ranks.isEmpty || ids.isEmpty) {
        return 0;
      }
      final d = deps();
      final dupes = <Dupe>[];
      for (final e in await firstValue(d.library.watch())) {
        final f = await lookup.of(e.key);
        if (f == null) continue;
        dupes.add(
          Dupe(
            entry: e,
            facts: f,
            health: ranks[e.sourceId],
            installed: ids.contains(e.sourceId),
          ),
        );
      }
      final plan = planMerges(dupes);
      var merged = 0;
      if (plan.isNotEmpty) await exportBackup(d);
      for (final g in plan) {
        for (final loser in g.losers) {
          await mergeInto(d, winner: g.winner, loser: loser);
          merged++;
        }
      }
      final now = clock();
      await local.set(dedupeLastRunKey, writeDate(now));
      if (merged > 0) {
        await log?.append(
          DiagnosticEntry(
            at: now,
            kind: dedupeKind,
            error: 'merged $merged into ${plan.length}',
          ),
        );
      }
      return merged;
    } finally {
      _run = null;
    }
  }
}
