/// Tracker contract (docs/DOCS-contracts.md §9).
///
/// Every tracking service (AniList, MyAnimeList) implements [Tracker];
/// `TrackingService` drives them from local reading progress.
library;

/// A remote tracking service such as AniList or MyAnimeList.
abstract interface class Tracker {
  /// Stable service id: `'anilist'` or `'mal'`.
  String get id;

  /// Human-readable service name.
  String get name;

  /// Whether a usable access token is stored.
  Future<bool> isLoggedIn();

  /// Runs the OAuth flow through `OAuthRedirect` (contracts §7).
  Future<void> login();

  /// Forgets the stored access token.
  Future<void> logout();

  /// Searches the remote catalogue for manga matching [title].
  Future<List<TrackSearchResult>> search(String title);

  /// Fetches the user's list entry for [remoteId], or `null` if the manga
  /// is not on the user's list.
  Future<TrackStatus?> fetch(String remoteId);

  /// Sets the remote chapter count to [chaptersRead]. Implementations never
  /// lower a remote count that is already higher.
  Future<void> pushProgress(String remoteId, int chaptersRead);
}

/// One remote search hit.
class TrackSearchResult {
  /// Creates a search hit.
  const TrackSearchResult({
    required this.remoteId,
    required this.title,
    this.coverUrl,
    this.chapters,
  });

  /// Remote media id.
  final String remoteId;

  /// Display title.
  final String title;

  /// Cover image URL, if the service has one.
  final String? coverUrl;

  /// Total chapter count, `null` while unknown or still publishing.
  final int? chapters;

  @override
  bool operator ==(Object other) =>
      other is TrackSearchResult &&
      other.remoteId == remoteId &&
      other.title == title &&
      other.coverUrl == coverUrl &&
      other.chapters == chapters;

  @override
  int get hashCode => Object.hash(remoteId, title, coverUrl, chapters);

  @override
  String toString() => 'TrackSearchResult($remoteId, $title)';
}

/// The user's list entry on a remote service.
class TrackStatus {
  /// Creates a list entry snapshot.
  const TrackStatus({
    required this.remoteId,
    required this.chaptersRead,
    required this.status,
    this.totalChapters,
    this.score,
  });

  /// Remote media id.
  final String remoteId;

  /// Chapters marked read remotely.
  final int chaptersRead;

  /// Total chapter count, `null` while unknown.
  final int? totalChapters;

  /// Service-specific list status, e.g. `CURRENT`, `COMPLETED`, `reading`.
  final String status;

  /// User score on the service's own scale, `null` when unscored.
  final double? score;

  @override
  bool operator ==(Object other) =>
      other is TrackStatus &&
      other.remoteId == remoteId &&
      other.chaptersRead == chaptersRead &&
      other.totalChapters == totalChapters &&
      other.status == status &&
      other.score == score;

  @override
  int get hashCode =>
      Object.hash(remoteId, chaptersRead, totalChapters, status, score);

  @override
  String toString() => 'TrackStatus($remoteId, $chaptersRead, $status)';
}
