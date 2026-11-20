import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/migration/candidates/candidate_finder.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_backup.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/migration/migrator.dart';
import 'package:kartka/migration/walk/walk_inputs.dart';
import 'package:kartka/migration/walk/walk_item.dart';

export 'package:kartka/migration/candidates/candidate_finder.dart';
export 'package:kartka/migration/walk/walk_inputs.dart';
export 'package:kartka/migration/walk/walk_item.dart';

/// State of the one-by-one migration: the entries to walk, the current one
/// and its alternatives (the next one's searched ahead). Nothing is written
/// until [migrateTo], which only a tap on a card calls; the library backup
/// is written before the first write of the session.
class MigrationWalkController extends ChangeNotifier {
  /// Walks [scope] (or only [onlyKeys]) migrating with the deps, over the
  /// inputs; [timeout] bounds each source request.
  new(
    this._deps,
    this._inputs, {
    this.scope = WalkScope.library,
    this.onlyKeys,
    this.timeout = const Duration(seconds: 15),
  });

  final MigrationDeps _deps;
  final MigrationInputs _inputs;

  /// Which entries to walk.
  final WalkScope scope;

  /// Only these entries, in library order, when set.
  final Set<MangaKey>? onlyKeys;

  /// Longest wait for one source request.
  final Duration timeout;

  /// Whether [load] has finished.
  bool loaded = false;

  /// The entries, in library order.
  List<WalkItem> items = const [];

  /// The current entry's place in [items] (== length when done).
  int index = 0;

  /// Whether a migration is being written.
  bool busy = false;

  /// Blob key of the backup, once written.
  String? backupKey;

  /// Why the backup failed (nothing moved; spoken, never painted).
  String? backupError;

  CandidateFinder? _finder;
  bool _disposed = false;

  /// The current entry; null when done or empty.
  WalkItem? get current => index < items.length ? items[index] : null;

  /// Entries migrated this session.
  int get migrated => items.where((i) => i.migratedTo != null).length;

  /// Entries whose migration failed this session.
  int get failed => items.where((i) => i.error != null).length;

  /// Shows the library's entries at once (the whole-library scope), then
  /// reads the health records, the run meta and the installed sources,
  /// picks the targets and searches the first entry and the next one.
  Future<void> load() async {
    final entries = await firstValue(_deps.library.watch());
    final keys = onlyKeys;
    if (keys != null || scope == WalkScope.library) {
      items = [
        for (final e in entries)
          if (keys?.contains(e.key) ?? true) WalkItem(e),
      ];
      loaded = true;
      _notify();
    }
    final (records, meta, sources) = await (
      _inputs.records(),
      _inputs.meta?.call() ?? Future.value(),
      _inputs.sources(),
    ).wait;
    final rejected = meta?.rejectedIds ?? const <String>{};
    final installed = {for (final s in sources) s.ref.id: s};
    final flagOf = _inputs.flagOf ?? (_) => null;
    final ranked = rankedTargets(
      records,
      installed,
      flagOf: flagOf,
      rejected: rejected,
    );
    MangaSource? atsumaru;
    for (final s in installed.values) {
      if (isAtsumaru(s.ref)) atsumaru = s;
    }
    _finder = CandidateFinder(
      migrationTargets([for (final t in ranked) t.source], atsumaru: atsumaru),
      timeout: timeout,
    );
    final byId = {for (final r in records) r.id: r};
    final server = installed.keys.any((id) => id.startsWith('suwayomi:'));
    bool listed(String id) =>
        installed.containsKey(id) || (!server && id.startsWith('suwayomi:'));
    if (!loaded) {
      items = [
        for (final e in entries)
          if (moveReason(
                record: byId[e.sourceId],
                installed: listed(e.sourceId),
                flag: flagOf(e.sourceId),
                rejected: rejected.contains(e.sourceId),
              ) !=
              null)
            WalkItem(e),
      ];
      loaded = true;
    }
    for (final i in items) {
      i
        ..own = installed[i.entry.sourceId]
        ..ownName = byId[i.entry.sourceId]?.name;
    }
    _ahead();
    _notify();
  }

  /// Searches the current and the next entry when not searched yet.
  void _ahead() {
    if (_finder == null) return;
    for (final i in [index, index + 1]) {
      if (i < items.length && items[i].pending == null) _search(items[i]);
    }
  }

  void _search(WalkItem item, {String? query}) {
    final finder = _finder;
    if (finder == null) return;
    item.found = null;
    late final Future<void> run;
    run = item.pending = () async {
      final progress = await firstValue(_deps.progress.watch(item.entry.key));
      void show(EntryCandidates found) {
        if (!identical(item.pending, run)) return;
        item.found = found;
        _notify();
      }

      show(
        await finder.find(
          item.entry,
          own: item.own,
          readChapter: progress?.chapterNumber,
          query: query,
          onUpdate: show,
        ),
      );
    }();
  }

  /// Searches the current entry for [query] instead (manual search).
  void search(String query) {
    final item = current;
    if (item == null || query.trim().isEmpty) return;
    _search(item, query: query.trim());
    _notify();
  }

  /// Goes to the next entry without migrating this one.
  void skip() => _go(index + 1);

  /// Goes back to the previous entry.
  void back() => _go(index - 1);

  void _go(int to) {
    if (busy || to < 0 || to > items.length) return;
    index = to;
    _ahead();
    _notify();
  }

  /// Backs up (once), moves the current entry to [to] with the migrator
  /// (progress, read marks, categories and trackers carry over), then goes
  /// to the next entry. A failed backup changes nothing.
  Future<void> migrateTo(MigrationCandidate to) async {
    final item = current;
    if (item == null || busy || item.migratedTo != null) return;
    busy = true;
    _notify();
    if (backupKey == null) {
      try {
        backupKey = await exportBackup(_deps);
      } on Object catch (e) {
        backupError = redactUrlQueries('$e');
        busy = false;
        return _notify();
      }
    }
    try {
      await migrateEntry(
        _deps,
        from: item.entry,
        target: to.source,
        to: to.manga,
      );
      item
        ..migratedTo = to
        ..error = null;
      busy = false;
      return _go(index + 1);
    } on Object catch (e) {
      item.error = redactUrlQueries('$e');
    }
    busy = false;
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
