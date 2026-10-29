/// Library-local ports (contracts §9 tail, §10).
///
/// The Library screen needs facts other parts own. Each port lives here, in
/// the consumer's directory; its owner registers a real implementation in
/// `KartkaFeature.services` and the screen picks it up with
/// `registry.maybe<T>()`, falling back to the no-op default below.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/manga_key.dart';

/// Unread chapter count per entry. Supplied by browse (chapter cache).
abstract interface class UnreadCounts {
  /// Emits the unread count for [key], or `null` when unknown.
  Stream<int?> watch(MangaKey key);
}

/// Whether an entry has offline chapters. Supplied by downloads.
abstract interface class DownloadedLookup {
  /// Emits `true` while at least one chapter of [key] is stored offline.
  Stream<bool> hasDownloads(MangaKey key);
}

/// Whether an entry is bound to a tracker. Supplied by tracking.
abstract interface class TrackedLookup {
  /// Emits `true` while [key] is bound to AniList or MAL.
  Stream<bool> isTracked(MangaKey key);
}

/// Default [UnreadCounts]: no badge.
class NoUnreadCounts implements UnreadCounts {
  /// Creates the no-op port.
  const new();

  @override
  Stream<int?> watch(MangaKey key) => Stream.value(null);
}

/// Default [DownloadedLookup]: nothing downloaded.
class NoDownloadedLookup implements DownloadedLookup {
  /// Creates the no-op port.
  const new();

  @override
  Stream<bool> hasDownloads(MangaKey key) => Stream.value(false);
}

/// Default [TrackedLookup]: nothing tracked.
class NoTrackedLookup implements TrackedLookup {
  /// Creates the no-op port.
  const new();

  @override
  Stream<bool> isTracked(MangaKey key) => Stream.value(false);
}

/// "Update all": checks every library manga for new chapters. Supplied by
/// updates; one shared run, so the Library and Updates tabs show the same
/// progress. Notifies listeners whenever [progress] changes.
abstract interface class LibraryUpdater implements Listenable {
  /// The run in flight, or `null` when idle.
  UpdateProgress? get progress;

  /// Checks every library manga; a call while a run is in flight joins it.
  Future<UpdateSummary> updateAll();
}

/// How far an update-all run is.
@immutable
class UpdateProgress {
  /// [done] of [total] manga checked.
  const new(this.done, this.total);

  /// Manga checked so far.
  final int done;

  /// Manga in the run.
  final int total;

  /// The progress line, e.g. `Checking 12/87`.
  String get label => 'Checking $done/$total';

  @override
  bool operator ==(Object other) =>
      other is UpdateProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);
}

/// What an update-all run found.
@immutable
class UpdateSummary {
  /// [newChapters] across [manga]; [failed] manga could not be checked,
  /// [notChecked] were skipped because their server was unreachable.
  const new({
    this.newChapters = 0,
    this.manga = 0,
    this.failed = 0,
    this.notChecked = 0,
  });

  /// New chapters found.
  final int newChapters;

  /// Manga with at least one new chapter.
  final int manga;

  /// Manga whose check failed (a source error, not the network).
  final int failed;

  /// Manga not checked because the network or their server was down.
  final int notChecked;

  /// The snackbar line.
  String get message => [
    if (newChapters == 0)
      'No new chapters'
    else
      '$newChapters new chapter${newChapters == 1 ? '' : 's'} in $manga manga',
    if (failed > 0) '$failed failed',
    if (notChecked > 0) 'offline: $notChecked not checked',
  ].join(' · ');
}
