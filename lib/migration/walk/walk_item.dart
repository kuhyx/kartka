import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/candidates/candidate_finder.dart';

/// Which library entries the walk goes through.
enum WalkScope {
  /// The whole library, in library order (More → Migrate).
  library,

  /// Entries whose source should be left (`moveReason`; "Migrate to better
  /// sources").
  better,
}

/// One library entry on the walk.
class WalkItem {
  /// The step for [entry]; [own] and [ownName] are filled in once the
  /// installed sources and the health records are read.
  new(this.entry, {this.own, this.ownName});

  /// The entry to migrate.
  final LibraryEntry entry;

  /// Its source, when installed.
  MangaSource? own;

  /// Its source's display name, when known.
  String? ownName;

  /// The search under way, once started.
  Future<void>? pending;

  /// What the search found.
  EntryCandidates? found;

  /// Where the entry went, once migrated.
  MigrationCandidate? migratedTo;

  /// Why its migration failed (redacted; spoken, never painted).
  String? error;

  /// The name shown for its source.
  String get sourceName => own?.ref.name ?? ownName ?? entry.sourceId;
}
