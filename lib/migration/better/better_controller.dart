import 'package:flutter/foundation.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/migration/better/better_row.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_backup.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migrator.dart';

export 'package:kartka/migration/better/better_row.dart';

/// Where the screen is.
enum BetterPhase {
  /// Finding the entries to move and searching their targets.
  loading,

  /// Searched; rows can be migrated.
  ready,

  /// "Migrate all" is running.
  migrating,

  /// "Migrate all" finished.
  done,
}

/// State of "Migrate to better sources". Searches only on [load]; nothing
/// moves until [migrate] or [migrateAll], which only explicit taps call,
/// and both write the library backup first (once per screen).
class BetterSourcesController extends ChangeNotifier {
  /// Creates the controller; [timeout] bounds each chapter-count request.
  new(this._deps, this._inputs, {this.timeout = const Duration(seconds: 20)});

  final MigrationDeps _deps;
  final BetterSourcesInputs _inputs;

  /// Longest wait for one chapter list.
  final Duration timeout;

  /// Current phase.
  BetterPhase phase = BetterPhase.loading;

  /// Entries that should move, in library order.
  List<BetterRow> rows = const [];

  /// Blob key of the backup, once written.
  String? backupKey;

  /// Why the backup failed (nothing moved), redacted.
  String? error;

  /// Entries moved so far.
  int migrated = 0;

  /// Entries whose migration failed.
  int failed = 0;

  bool _disposed = false;

  /// Rows that can still be migrated.
  int get pending => rows.where((r) => r.canMigrate).length;

  /// Finds the entries to move and searches the keep sources, best rank
  /// first, stopping at the first one with the title (one request at a
  /// time: sources rate-limit).
  Future<void> load() async {
    final records = await _inputs.records();
    final installed = {for (final s in await _inputs.sources()) s.ref.id: s};
    final flagOf = _inputs.flagOf ?? (_) => null;
    final byId = {for (final r in records) r.id: r};
    final targets = keepTargets(records, installed, flagOf: flagOf);
    rows = [
      for (final e in await firstValue(_deps.library.watch()))
        if (moveReason(
              record: byId[e.sourceId],
              installed: installed.containsKey(e.sourceId),
              flag: flagOf(e.sourceId),
            )
            case final why?)
          BetterRow(e, why, current: byId[e.sourceId]),
    ];
    _notify();
    for (final row in rows) {
      if (_disposed) return;
      await _search(row, targets, installed[row.entry.sourceId]);
      row.searched = true;
      _notify();
    }
    phase = BetterPhase.ready;
    _notify();
  }

  Future<void> _search(
    BetterRow row,
    List<KeepTarget> targets,
    MangaSource? current,
  ) async {
    for (final t in targets) {
      if (t.source.ref.id == row.entry.sourceId) continue;
      try {
        final found = (await t.source.search(row.entry.title, 1)).items;
        final m = titleMatch(row.entry.title, found);
        if (m == null) continue;
        row
          ..target = t
          ..match = m
          ..targetChapters = await _count(t.source, m.url)
          ..currentChapters = current == null
              ? null
              : await _count(current, row.entry.mangaUrl);
        return;
      } on Object {
        continue; // That source is down; the next one may have it.
      }
    }
  }

  Future<int?> _count(MangaSource source, String url) async {
    try {
      return (await source.chapters(url).timeout(timeout)).length;
    } on Object {
      return null;
    }
  }

  Future<bool> _backup() async {
    if (backupKey != null) return true;
    try {
      backupKey = await exportBackup(_deps);
      return true;
    } on Object catch (e) {
      error = redactUrlQueries('$e');
      _notify();
      return false;
    }
  }

  /// Backs up (once), then moves [row] to its suggestion with the
  /// migrator: progress, read marks, categories and trackers carry over.
  Future<void> migrate(BetterRow row) async {
    if (!row.canMigrate || !await _backup()) return;
    row.busy = true;
    _notify();
    try {
      await migrateEntry(
        _deps,
        from: row.entry,
        target: row.target!.source,
        to: row.match!,
      );
      row.migrated = true;
      migrated++;
    } on Object catch (e) {
      row.error = redactUrlQueries('$e');
      failed++;
    }
    row.busy = false;
    _notify();
  }

  /// Migrates every row that has a suggestion, one at a time (after the
  /// user confirmed). Does nothing when none has one.
  Future<void> migrateAll() async {
    final todo = rows.where((r) => r.canMigrate).toList();
    if (todo.isEmpty || !await _backup()) return;
    phase = BetterPhase.migrating;
    _notify();
    for (final row in todo) {
      await migrate(row);
    }
    phase = BetterPhase.done;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
