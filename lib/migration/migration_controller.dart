import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/migration_backup.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/migration/migrator.dart';

/// Where the review screen is.
enum MigrationPhase {
  /// Looking for Atsumaru, then searching it entry by entry.
  searching,

  /// Atsumaru is not installed: nothing can be migrated.
  unavailable,

  /// Every entry searched; waiting for the user to tap Apply.
  ready,

  /// Backing up, then migrating the ticked rows.
  applying,

  /// Applied (see `migrated` / `failed`).
  done,

  /// The backup failed, so nothing was changed.
  failed,
}

/// One library entry under review and its best Atsumaru match.
class MigrationRow {
  /// Creates the row for [entry].
  new(this.entry);

  /// The entry to migrate.
  final LibraryEntry entry;

  /// The best Atsumaru match (an exact title first, else the top result).
  MangaSummary? candidate;

  /// Whether Apply migrates this row.
  bool ticked = false;

  /// Whether the search for this row finished.
  bool searched = false;

  /// Why the search or the migration of this row failed (redacted).
  String? error;

  /// Whether [candidate] has exactly the entry's title.
  bool get exact =>
      candidate != null && isExactTitle(entry.title, candidate!.title);
}

/// State of the "Migrate to Atsumaru" review screen. Nothing is written
/// until [apply], which only an explicit tap calls.
class MigrationController extends ChangeNotifier {
  /// Reviews [onlyKeys] (every entry not on Atsumaru when null).
  new(this._deps, {this.onlyKeys});

  final MigrationDeps _deps;

  /// The entries to review; null means the whole library.
  final Set<MangaKey>? onlyKeys;

  /// Current phase.
  MigrationPhase phase = MigrationPhase.searching;

  /// Rows in library order.
  List<MigrationRow> rows = const [];

  /// The Atsumaru source, once found.
  MangaSource? target;

  /// Blob key of the backup written by [apply].
  String? backupKey;

  /// Rows migrated by [apply].
  int migrated = 0;

  /// Rows whose migration failed.
  int failed = 0;

  /// Why [apply] stopped (the backup failed), redacted.
  String? error;

  bool _disposed = false;

  /// Whether Apply can be tapped.
  bool get canApply =>
      phase == MigrationPhase.ready && rows.any((r) => r.ticked);

  /// Finds Atsumaru, lists the entries and searches each one in turn (one
  /// request at a time: sources rate-limit).
  Future<void> load() async {
    final target = this.target = await _deps.findTarget();
    if (target == null) {
      phase = MigrationPhase.unavailable;
      return _notify();
    }
    final keys = onlyKeys;
    rows = [
      for (final e in await _deps.library.watch().first)
        if (e.sourceId != target.ref.id &&
            (keys == null || keys.contains(e.key)))
          MigrationRow(e),
    ];
    _notify();
    for (final row in rows) {
      if (_disposed) return;
      try {
        final found = (await target.search(row.entry.title, 1)).items;
        row
          ..candidate =
              found.firstWhereOrNull(
                (m) => isExactTitle(row.entry.title, m.title),
              ) ??
              found.firstOrNull
          ..ticked = row.exact;
      } on Object catch (e) {
        row.error = redactUrlQueries('$e');
      }
      row.searched = true;
      _notify();
    }
    phase = MigrationPhase.ready;
    _notify();
  }

  /// Ticks or unticks [row]; a row without a candidate stays unticked.
  void setTicked(MigrationRow row, {required bool ticked}) {
    row.ticked = ticked && row.candidate != null;
    _notify();
  }

  /// Exports a backup, then migrates every ticked row. When the backup
  /// fails nothing is written.
  Future<void> apply() async {
    if (!canApply) return;
    phase = MigrationPhase.applying;
    _notify();
    try {
      backupKey = await exportBackup(_deps);
    } on Object catch (e) {
      error = redactUrlQueries('$e');
      phase = MigrationPhase.failed;
      return _notify();
    }
    for (final row in rows.where((r) => r.ticked)) {
      try {
        await migrateEntry(
          _deps,
          from: row.entry,
          target: target!,
          to: row.candidate!,
        );
        migrated++;
        row.ticked = false;
      } on Object catch (e) {
        failed++;
        row.error = redactUrlQueries('$e');
      }
      _notify();
    }
    phase = MigrationPhase.done;
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
