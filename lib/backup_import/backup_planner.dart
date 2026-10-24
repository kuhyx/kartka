import 'dart:convert';

import 'package:kartka/backup_import/backup_models.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/core/models/models.dart';

/// Kartka tracker service name for a Tachiyomi tracker id.
String trackerService(int syncId) => switch (syncId) {
  1 => 'mal',
  2 => 'anilist',
  3 => 'kitsu',
  4 => 'shikimori',
  5 => 'bangumi',
  6 => 'komga',
  7 => 'mangaupdates',
  8 => 'kavita',
  9 => 'suwayomi',
  60 => 'mdlist',
  _ => 'tracker$syncId',
};

/// Services whose bindings Kartka can use (DOCS-contracts §9).
const Set<String> _boundServices = {'anilist', 'mal'};

DateTime _ms(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// Turns a decoded backup into Kartka writes, deterministically and without
/// touching any repository (so the same plan feeds dry run and import).
class BackupPlanner {
  /// Creates a planner using [mapper] for source ids.
  const new(this.mapper);

  /// Source id mapping.
  final SourceMapper mapper;

  /// Plans the import of [data].
  ImportPlan plan(BackupData data) {
    final categories = _categories(data);
    final idByOrder = {for (final c in categories) c.order: c.id};
    final names = {for (final s in data.sources) s.sourceId: s.name};
    final seen = <String>{};
    final planned = <PlannedManga>[];
    final unmapped = <String, int>{};
    final byService = <String, int>{};
    var notInLibrary = 0;
    var duplicates = 0;
    for (final m in data.manga) {
      if (!m.favorite) {
        notInLibrary++;
        continue;
      }
      final source = mapper.map(m.sourceId);
      final pm = _manga(m, source, idByOrder);
      if (!seen.add(pm.entry.key)) {
        duplicates++;
        continue;
      }
      if (source.kind == SourceKind.unmapped) {
        unmapped.update(m.sourceId, (n) => n + 1, ifAbsent: () => 1);
      }
      planned.add(pm);
      for (final t in m.tracking.where((t) => t.mediaId != '0')) {
        byService.update(
          trackerService(t.syncId),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return ImportPlan(
      manga: planned,
      categories: categories,
      summary: _summary(
        planned,
        categories.length,
        byService,
        unmapped: [
          for (final e in unmapped.entries)
            UnmappedSource(names[e.key] ?? '', e.key, e.value),
        ],
        notInLibrary: notInLibrary,
        duplicates: duplicates,
      ),
    );
  }

  List<PlannedCategory> _categories(BackupData data) {
    final seen = <int>{};
    return [
      for (final c in data.categories)
        if (seen.add(c.order))
          PlannedCategory(
            id: _categoryId(c.name),
            name: c.name,
            order: c.order,
          ),
    ];
  }

  PlannedManga _manga(
    BackupManga m,
    MappedSource source,
    Map<int, String> idByOrder,
  ) {
    final key = mangaKeyOf(source.sourceId, m.url);
    final addedAt = _ms(m.dateAdded);
    final entry = LibraryEntry(
      key: key,
      sourceId: source.sourceId,
      mangaUrl: m.url,
      title: _firstNonEmpty(m.customTitle, m.title),
      coverUrl: _firstNonEmpty(
        m.customThumbnailUrl,
        m.thumbnailUrl,
      ).nullIfEmpty,
      addedAt: addedAt,
      updatedAt: m.lastModifiedAt > 0 ? _ms(m.lastModifiedAt * 1000) : addedAt,
    );
    final read = <String>{
      for (final c in m.chapters)
        if (c.read) c.url,
    }.toList();
    return PlannedManga(
      entry: entry,
      categoryIds: {
        for (final o in m.categories)
          if (idByOrder[o] != null) idByOrder[o]!,
      }.toList(),
      readChapterUrls: read,
      progress: _progress(m, key),
      bindings: _bindings(m),
    );
  }

  /// Highest-numbered chapter that was read or opened; ties go to the later
  /// page. Chapters with no usable number cannot be ordered, so they only
  /// get a read mark.
  ReadingProgress? _progress(BackupManga m, MangaKey key) {
    BackupChapter? best;
    for (final c in m.chapters) {
      if (c.number < 0 || !(c.read || c.lastPageRead > 0)) continue;
      if (best == null ||
          c.number > best.number ||
          (c.number == best.number && c.lastPageRead > best.lastPageRead)) {
        best = c;
      }
    }
    if (best == null) return null;
    final lastRead = {for (final h in m.history) h.url: h.lastRead};
    final ms =
        lastRead[best.url] ??
        lastRead.values.fold<int>(0, (a, b) => a > b ? a : b);
    return ReadingProgress(
      key: key,
      chapterUrl: best.url,
      chapterNumber: best.number,
      page: best.lastPageRead,
      readAt: ms > 0 ? _ms(ms) : _ms(m.dateAdded),
    );
  }

  List<PlannedBinding> _bindings(BackupManga m) {
    final out = <String, PlannedBinding>{};
    for (final t in m.tracking) {
      final service = trackerService(t.syncId);
      if (!_boundServices.contains(service) || t.mediaId == '0') continue;
      out.putIfAbsent(
        service,
        () => PlannedBinding(service, t.mediaId, t.lastChapterRead.floor()),
      );
    }
    return out.values.toList();
  }

  ImportSummary _summary(
    List<PlannedManga> planned,
    int categoryCount,
    Map<String, int> byService, {
    required List<UnmappedSource> unmapped,
    required int notInLibrary,
    required int duplicates,
  }) {
    return ImportSummary(
      entries: planned.length,
      categories: categoryCount,
      memberships: planned.fold(0, (n, m) => n + m.categoryIds.length),
      chaptersRead: planned.fold(0, (n, m) => n + m.readChapterUrls.length),
      trackersByService: byService,
      trackersImported: planned.fold(0, (n, m) => n + m.bindings.length),
      unmappedSources: unmapped,
      notInLibrary: notInLibrary,
      duplicates: duplicates,
    );
  }
}

String _firstNonEmpty(String? a, String? b) =>
    (a != null && a.isNotEmpty) ? a : (b ?? '');

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

String _categoryId(String name) {
  final hex = utf8
      .encode(name.toLowerCase())
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'sy-$hex';
}
