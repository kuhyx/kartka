import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

/// The screenshot's title.
const dream = 'I Had That Same Dream Again';

/// Pinned "now" of every dedupe test.
final dedupeNow = DateTime.utc(2026, 11, 21, 12);

/// A keep source at [rank].
SourceHealthSummary keepAt(int rank) =>
    SourceHealthSummary(verdict: HealthVerdict.keep, rank: rank);

/// Stored facts per key, the way browse's port answers.
class FakeDupeFacts implements DupeFactsLookup {
  final Map<MangaKey, DupeFacts> byKey = {};

  @override
  Future<DupeFacts?> of(MangaKey key) async => byKey[key];
}

/// A [World] plus the deduper's inputs.
class DedupeWorld {
  new({World? world}) : w = world ?? World();

  final World w;
  final facts = FakeDupeFacts();
  Map<String, SourceHealthSummary>? health = {};
  Set<String> installed = {};
  final local = MemoryKeyValueStore();
  final diag = MemoryBlobStore();
  DateTime now = dedupeNow;

  /// A deduper over this world.
  LibraryDeduper make({LibraryUpdater? updater}) => LibraryDeduper(
    deps: () => w.deps,
    facts: () => facts,
    health: () async => health,
    installed: () async => installed,
    local: local,
    updater: () => updater,
    log: DiagnosticsLog(diag),
    clock: () => now,
  );

  /// Adds [title] on [source] (installed, ranked [rank] when given) with
  /// [count] stored chapters, the first [read] of them read.
  Future<LibraryEntry> add(
    String source, {
    String title = dream,
    List<String> authors = const [],
    String? description,
    int count = 12,
    int read = 0,
    int? rank,
    DateTime? added,
  }) async {
    final url = '/$source';
    final e = LibraryEntry(
      key: mangaKeyOf(source, url),
      sourceId: source,
      mangaUrl: url,
      title: title,
      addedAt: added ?? DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    await w.repos.library.upsert(e);
    installed.add(source);
    if (rank != null) health![source] = keepAt(rank);
    final chapters = chaptersOf(source, [for (var n = 1; n <= count; n++) n]);
    facts.byKey[e.key] = (
      details: MangaDetails(
        sourceId: source,
        url: url,
        title: title,
        authors: authors,
        description: description,
      ),
      chapters: chapters,
      readUrls: {for (final c in chapters.take(read)) c.url},
    );
    return e;
  }

  /// Explicitly read chapter urls of [e].
  Future<Set<String>> readOf(LibraryEntry e) async => {
    for (final m in (await w.repos.progress.readMarks(e.key).first).entries)
      if (m.value) m.key,
  };

  /// Categories [e] is in.
  Future<Set<String>> categoriesOf(LibraryEntry e) async =>
      (await w.repos.categories.watchMembership().first)[e.key] ?? const {};

  /// Backup blobs written so far.
  Future<List<String>> backups() => w.backups.list('backups/');
}
