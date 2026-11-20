import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/state/auto_shelve_rule.dart';
import 'package:kartka/library/state/category_actions.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/platform/key_value_store.dart';

export 'package:kartka/library/state/auto_shelve_rule.dart';

/// Entries one run moved, per shelf.
typedef ShelveCounts = ({int finished, int abandoned});

/// Diagnostics kind of the line a run that moved something logs (it stays
/// on the device: `deviceOnlyKinds`).
const autoShelveKind = 'library.autoshelve';

/// Synced settings key (§16) of the rule's memory: manga key to the newest
/// chapter upload it last saw shelved, as a JSON object.
const autoShelveMemoryKey = 'library.autoshelve';

/// Device-local key of the last run's instant (the start-up gate).
const autoShelveLastRunKey = 'library.autoshelve.lastRun';

/// The start-up run is skipped when a run finished less than this ago.
const shelveEvery = Duration(hours: 6);

/// Moves stale entries to their shelf (DOCS-spec "Auto-shelving").
///
/// A stale entry (newest chapter older than [staleCutoff]) ends in exactly
/// one category: [Shelf.finished] when every chapter is read, else
/// [Shelf.abandoned]. The newest upload it was seen shelved at is
/// remembered in [memory]; while that is unchanged the entry is never moved
/// again, so a manual move-out sticks. An entry already in its shelf is
/// left alone but remembered too, since another device may have moved it.
class AutoShelver {
  /// Creates the shelver; ports are read lazily (the registry is complete
  /// only after every feature factory ran).
  new({
    required this.repos,
    required this.facts,
    required this.memory,
    required this.local,
    required this.updater,
    this.log,
    this.clock = utcNow,
  });

  /// Decorated repositories, so sync sees the membership writes.
  final LibraryRepositories repos;

  /// Newest upload and read state per entry (browse).
  final ShelfFactsLookup Function() facts;

  /// Where [autoShelveMemoryKey] lives (the synced settings store).
  final KeyValueStore memory;

  /// Where [autoShelveLastRunKey] lives (device-local).
  final KeyValueStore local;

  /// The shared "update all" run; each finished run triggers [run].
  final LibraryUpdater? Function() updater;

  /// Where a run that moved something logs its counts.
  final DiagnosticsLog? log;

  /// Clock deciding staleness and the start-up gate.
  final DateTime Function() clock;

  late final _actions = CategoryActions(
    LibraryDeps(repos: repos, clock: clock),
  );
  Future<ShelveCounts>? _run;
  bool _started = false;

  /// Completes when no run is in flight.
  Future<void> get idle => _run ?? Future.value();

  /// Once per launch (the library's first load): follows [updater], then
  /// runs unless a run finished within [shelveEvery].
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _follow();
    final last = DateTime.tryParse(await local.get(autoShelveLastRunKey) ?? '');
    if (last != null && clock().difference(last) < shelveEvery) return;
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

  /// Shelves every stale entry; a call while a run is in flight joins it.
  Future<ShelveCounts> run() => _run ??= _runOnce();

  Future<ShelveCounts> _runOnce() async {
    try {
      final now = clock();
      final counts = await _shelve(now);
      await local.set(autoShelveLastRunKey, writeDate(now));
      final moved = counts.finished + counts.abandoned;
      if (moved > 0) {
        await log?.append(
          DiagnosticEntry(
            at: now,
            kind: autoShelveKind,
            error:
                'moved $moved: finished ${counts.finished}, '
                'abandoned ${counts.abandoned}',
          ),
        );
      }
      return counts;
    } finally {
      _run = null;
    }
  }

  Future<ShelveCounts> _shelve(DateTime now) async {
    final entries = await repos.library.watch().first;
    var live = await repos.categories.watch().first;
    final members = await repos.categories.watchMembership().first;
    final raw = await memory.get(autoShelveMemoryKey);
    final seen = _decode(raw);
    final remembered = SplayTreeMap<String, String>();
    final moved = {for (final s in Shelf.values) s: 0};
    final lookup = facts();
    for (final e in entries) {
      final f = await lookup.of(e.key);
      final newest = f?.newestUpload;
      if (f == null || newest == null || !isStale(newest, now)) continue;
      remembered[e.key] = writeDate(newest);
      if (sameInstant(DateTime.tryParse(seen[e.key] ?? ''), newest)) continue;
      final shelf = f.allRead ? Shelf.finished : Shelf.abandoned;
      var target = shelfCategory(shelf, live);
      if (target == null) {
        target = await _actions.create(
          shelf.name,
          live,
          id: autoShelfId(shelf),
        );
        live = [...live, target!];
      }
      final inIt = members[e.key] ?? const {};
      if (inIt.contains(target.id)) continue;
      await repos.categories.setMembership(e.key, target.id, true);
      for (final c in live) {
        if (c.id != target.id && inIt.contains(c.id)) {
          await repos.categories.setMembership(e.key, c.id, false);
        }
      }
      moved[shelf] = moved[shelf]! + 1;
    }
    final next = jsonEncode(remembered);
    if (next != (raw ?? '{}')) await memory.set(autoShelveMemoryKey, next);
    return (
      finished: moved[Shelf.finished]!,
      abandoned: moved[Shelf.abandoned]!,
    );
  }

  static Map<String, String> _decode(String? raw) {
    try {
      return Map<String, String>.from(jsonDecode(raw ?? '{}') as Map);
    } on Object {
      // A corrupt memory forgets, rather than stopping every later run.
      return const {};
    }
  }
}
