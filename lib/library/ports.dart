/// Library-local ports (contracts §9 tail, §10).
///
/// The Library screen needs facts other parts own. Each port lives here, in
/// the consumer's directory; its owner registers a real implementation in
/// `KartkaFeature.services` and the screen picks it up with
/// `registry.maybe<T>()`, falling back to the no-op default below.
library;

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
