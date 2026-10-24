import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';

/// What an import wrote (zero everywhere on a repeat run).
class ImportResult {
  /// Creates a result.
  const ImportResult({
    this.entries = 0,
    this.categories = 0,
    this.memberships = 0,
    this.readMarks = 0,
    this.progress = 0,
    this.bindings = 0,
  });

  /// Library entries written.
  final int entries;

  /// Categories created.
  final int categories;

  /// Memberships set.
  final int memberships;

  /// Chapters newly marked read.
  final int readMarks;

  /// Progress records written.
  final int progress;

  /// Tracker bindings written.
  final int bindings;

  /// True when the library already contained everything.
  bool get changedNothing =>
      entries + categories + memberships + readMarks + progress + bindings == 0;
}

/// Writes an [ImportPlan] through the §8 repositories.
///
/// Idempotent by construction: every write is preceded by a read of what is
/// already there, so a second run does nothing, and the user's own edits
/// (renamed titles, further progress, existing categories) are never
/// overwritten.
class BackupImporter {
  /// Creates an importer. [bindings] may be null when no tracking part is
  /// installed; tracker bindings are then skipped.
  const BackupImporter({
    required this.library,
    required this.categories,
    required this.progress,
    this.bindings,
  });

  /// Library repository.
  final LibraryRepository library;

  /// Category repository.
  final CategoryRepository categories;

  /// Progress repository.
  final ProgressRepository progress;

  /// Tracker binding sink, if any.
  final TrackerBindingSink? bindings;

  /// Applies [plan]; [onProgress] gets (entriesDone, entriesTotal).
  Future<ImportResult> apply(
    ImportPlan plan, {
    void Function(int done, int total)? onProgress,
  }) async {
    final known = {for (final e in await library.watch().first) e.key};
    final members = await categories.watchMembership().first;
    var createdCategories = 0;
    final idFor = <String, String>{};
    final byName = {
      for (final c in await categories.watch().first)
        if (!c.removed) c.name.toLowerCase(): c.id,
    };
    for (final c in plan.categories) {
      final existing = byName[c.name.toLowerCase()];
      idFor[c.id] = existing ?? c.id;
      if (existing != null) continue;
      await categories.upsert(
        Category(
          id: c.id,
          name: c.name,
          order: c.order,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
      createdCategories++;
    }

    var entries = 0;
    var memberships = 0;
    var marks = 0;
    var records = 0;
    var bound = 0;
    var done = 0;
    for (final m in plan.manga) {
      final key = m.entry.key;
      if (!known.contains(key)) {
        await library.upsert(m.entry);
        entries++;
      }
      for (final planned in m.categoryIds) {
        final id = idFor[planned]!;
        if (members[key]?.contains(id) ?? false) continue;
        await categories.setMembership(key, id, true);
        memberships++;
      }
      final alreadyRead = await progress.readChapters(key).first;
      for (final url in m.readChapterUrls.where(
        (u) => !alreadyRead.contains(u),
      )) {
        await progress.markRead(key, url);
        marks++;
      }
      final p = m.progress;
      if (p != null && p.isAheadOf(await progress.watch(key).first)) {
        await progress.record(p);
        records++;
      }
      final sink = bindings;
      for (final b in sink == null ? const <PlannedBinding>[] : m.bindings) {
        if (await sink!.bind(
          key,
          b.service,
          b.remoteId,
          lastPushedChapter: b.lastChapter,
        )) {
          bound++;
        }
      }
      onProgress?.call(++done, plan.manga.length);
      // Let the UI paint during the ~hundreds of entries.
      if (done % 25 == 0) await Future<void>.delayed(Duration.zero);
    }
    return ImportResult(
      entries: entries,
      categories: createdCategories,
      memberships: memberships,
      readMarks: marks,
      progress: records,
      bindings: bound,
    );
  }
}
