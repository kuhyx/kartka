import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/same_manga.dart';

/// One series a library entry can migrate to.
class MigrationCandidate {
  /// Creates the candidate.
  const new({
    required this.source,
    required this.manga,
    required this.score,
    required this.rank,
    this.chapters,
    this.newest,
  });

  /// The source it is on.
  final MangaSource source;

  /// The listing (title, url, cover).
  final MangaSummary manga;

  /// How sure the match is ([SameManga.score]).
  final double score;

  /// Its source's place among the targets (0 = best).
  final int rank;

  /// How many chapters it lists; null when unknown.
  final int? chapters;

  /// Upload time of its newest chapter; null when unknown.
  final DateTime? newest;

  /// Best first: by [score], then [rank], then more [chapters], then the
  /// newer [newest].
  static int compare(MigrationCandidate a, MigrationCandidate b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final byCount = (b.chapters ?? -1).compareTo(a.chapters ?? -1);
    if (byCount != 0) return byCount;
    final epoch = DateTime.utc(0);
    return (b.newest ?? epoch).compareTo(a.newest ?? epoch);
  }
}

/// How one target source's search went.
enum LaneState {
  /// Its search is still running.
  searching,

  /// It listed at least one usable hit.
  found,

  /// It answered, with nothing like the title.
  empty,

  /// It failed or timed out.
  failed,
}

/// One target source and how its search went.
typedef Lane = ({MangaSource source, LaneState state});

/// Everything found for one library entry.
class EntryCandidates {
  /// Creates the result.
  const new({
    required this.wanted,
    required this.lanes,
    required this.best,
    this.ownChapters,
    this.ownNewest,
  });

  /// What was known about the entry.
  final MangaFacts wanted;

  /// Every searched source, in target order.
  final List<Lane> lanes;

  /// The alternatives, best first ([MigrationCandidate.compare]).
  final List<MigrationCandidate> best;

  /// Chapters on the entry's own source; null when unknown.
  final int? ownChapters;

  /// Newest chapter upload on the entry's own source; null when unknown.
  final DateTime? ownNewest;
}

/// Upload time of the newest of [chapters]; null when none has one.
DateTime? newestOf(List<ChapterInfo>? chapters) {
  DateTime? newest;
  for (final c in chapters ?? const <ChapterInfo>[]) {
    final at = c.uploadedAt;
    if (at != null && (newest == null || at.isAfter(newest))) newest = at;
  }
  return newest;
}
