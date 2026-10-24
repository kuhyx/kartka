import 'package:kartka/core/models/models.dart';

/// A category to create (or match by name) on import.
class PlannedCategory {
  /// Creates a planned category.
  const new({required this.id, required this.name, required this.order});

  /// Deterministic id derived from the name (`sy-<hex>`), so re-importing
  /// never creates a second copy.
  final String id;

  /// Display name.
  final String name;

  /// Sort order from the backup.
  final int order;
}

/// A tracker binding to store.
class PlannedBinding {
  /// Creates a planned binding.
  const new(this.service, this.remoteId, this.lastChapter);

  /// `anilist` or `mal`.
  final String service;

  /// Remote media id.
  final String remoteId;

  /// Chapter the tracker already knows about (floor of the backup value).
  final int lastChapter;
}

/// Everything to write for one library entry.
class PlannedManga {
  /// Creates a planned manga.
  const new({
    required this.entry,
    required this.tachiyomiSourceId,
    required this.categoryIds,
    required this.readChapterUrls,
    required this.progress,
    required this.bindings,
  });

  /// The library entry.
  final LibraryEntry entry;

  /// The entry's Tachiyomi source id in the backup.
  final String tachiyomiSourceId;

  /// Planned category ids (see [PlannedCategory.id]).
  final List<String> categoryIds;

  /// Chapters marked read in the backup.
  final List<String> readChapterUrls;

  /// Last-read position, if any chapter has a usable number.
  final ReadingProgress? progress;

  /// Tracker bindings to store.
  final List<PlannedBinding> bindings;
}

/// A source with no way to open its entries right now.
class UnavailableSource {
  /// Creates an unavailable-source record.
  const new(this.name, this.id, this.entries);

  /// Name from the backup's source table (`''` if absent).
  final String name;

  /// Tachiyomi numeric id.
  final String id;

  /// Library entries that use it.
  final int entries;
}

/// Counts shown by the dry run.
class ImportSummary {
  /// Creates a summary.
  const new({
    required this.entries,
    required this.categories,
    required this.memberships,
    required this.chaptersRead,
    required this.trackersByService,
    required this.trackersImported,
    required this.notInLibrary,
    required this.duplicates,
  });

  /// Library entries to import.
  final int entries;

  /// Categories in the backup.
  final int categories;

  /// Entry/category memberships.
  final int memberships;

  /// Chapters marked read.
  final int chaptersRead;

  /// Tracker bindings in the backup, by service (all services).
  final Map<String, int> trackersByService;

  /// Bindings that will actually be stored (AniList and MAL).
  final int trackersImported;

  /// History-only records skipped because they are not in the library.
  final int notInLibrary;

  /// Records skipped because an earlier one had the same key.
  final int duplicates;
}

/// Pure result of reading a backup: no repository has been touched.
class ImportPlan {
  /// Creates a plan.
  const new({
    required this.manga,
    required this.categories,
    required this.summary,
    required this.sourceNames,
  });

  /// Entries to write.
  final List<PlannedManga> manga;

  /// Categories to create or match.
  final List<PlannedCategory> categories;

  /// Dry-run counts.
  final ImportSummary summary;

  /// Tachiyomi source id to name, from the backup's source table.
  final Map<String, String> sourceNames;

  /// Entries whose source cannot be opened, grouped by Tachiyomi id (most
  /// entries first). They are imported anyway. [available] holds the Kartka
  /// source ids that exist right now; `null` means unknown, so only SY
  /// built-ins (which never load) are listed.
  List<UnavailableSource> unavailable(Set<String>? available) {
    final counts = <String, int>{};
    for (final m in manga) {
      final id = m.entry.sourceId;
      final missing =
          id.startsWith('sy-builtin:') ||
          (available != null && !available.contains(id));
      if (missing) {
        counts.update(m.tachiyomiSourceId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final ids = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [
      for (final id in ids)
        UnavailableSource(sourceNames[id] ?? '', id, counts[id]!),
    ];
  }
}
