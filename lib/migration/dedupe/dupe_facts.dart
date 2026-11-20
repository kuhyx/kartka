import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/same_manga.dart';

/// What this device stored of one library entry: its last fetched details
/// (null when never fetched), its chapter list and which of them are read
/// (browse's read rule: explicit marks, else below the progress chapter).
typedef DupeFacts = ({
  MangaDetails? details,
  List<ChapterInfo> chapters,
  Set<String> readUrls,
});

/// [DupeFacts] from browse's stores. Supplied by browse.
abstract interface class DupeFactsLookup {
  /// Facts of [key]; null when this device never stored its chapters.
  /// Never fetches.
  Future<DupeFacts?> of(MangaKey key);
}

/// One library entry as duplicate merging judges it.
class Dupe {
  /// Creates the candidate.
  const new({
    required this.entry,
    required this.facts,
    this.health,
    this.installed = false,
  });

  /// The library entry.
  final LibraryEntry entry;

  /// What this device stored of it.
  final DupeFacts facts;

  /// Its source's evaluator summary; null when the source has no record.
  final SourceHealthSummary? health;

  /// Whether its source is installed right now.
  final bool installed;

  /// The matcher's view: title, alt titles, authors, description, count.
  MangaFacts get manga =>
      MangaFacts(title: entry.title)
          .withDetails(facts.details, chapters: facts.chapters.length);

  /// The newest chapter upload; null when no chapter is dated.
  DateTime? get newestUpload {
    DateTime? newest;
    for (final c in facts.chapters) {
      final at = c.uploadedAt;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    return newest;
  }
}
