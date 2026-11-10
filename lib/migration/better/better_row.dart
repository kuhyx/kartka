import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// What the screen reads besides the library: the scored source-health
/// records, the installed sources and the Keep auto-install's flags.
class BetterSourcesInputs {
  /// Creates the inputs; without [flagOf] no source counts as failing.
  const new({required this.records, required this.sources, this.flagOf});

  /// The source-health records under the active profile.
  final Future<List<SourceHealthRecord>> Function() records;

  /// Every installed source (after the providers settled).
  final Future<List<MangaSource>> Function() sources;

  /// The auto-install flag of a source id, if any.
  final String? Function(String id)? flagOf;
}

/// One library entry that should move, and its suggestion.
class BetterRow {
  /// Creates the row for [entry], which should move because of [reason].
  new(this.entry, this.reason, {this.current});

  /// The entry to move.
  final LibraryEntry entry;

  /// Why it should move.
  final MoveReason reason;

  /// Its current source's record; null when unknown.
  final SourceHealthRecord? current;

  /// The suggested source and its record.
  KeepTarget? target;

  /// The same series on [target].
  MangaSummary? match;

  /// Chapters on the current source; null when unknown.
  int? currentChapters;

  /// Chapters on the suggested source; null when unknown.
  int? targetChapters;

  /// Whether the search finished.
  bool searched = false;

  /// Whether the entry has moved.
  bool migrated = false;

  /// Whether its migration is running.
  bool busy = false;

  /// Why its migration failed (redacted).
  String? error;

  /// Whether [match] has exactly the entry's title.
  bool get exact => match != null && isExactTitle(entry.title, match!.title);

  /// Whether it can be migrated now.
  bool get canMigrate => match != null && !migrated && !busy;
}
