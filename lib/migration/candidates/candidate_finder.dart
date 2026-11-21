import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/candidates/migration_candidate.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/source_health/install/keep_plan.dart';

export 'package:kartka/migration/candidates/migration_candidate.dart';

/// Target sources searched per entry at most (the entry's own excluded).
const int maxTargets = 5;

/// Alternatives kept per entry.
const int maxCandidates = 5;

/// Hits per entry whose details (authors, description) are fetched.
const int detailedHits = 3;

/// Alt titles searched per source when the title finds nothing good.
const int maxAltQueries = 3;

/// Lowest title score of a hit worth keeping.
const double minTitleScore = 0.5;

/// [keep] (installed keep sources, best rank first) with [atsumaru] put
/// among the first [maxTargets] when installed and not already listed.
List<MangaSource> migrationTargets(
  List<MangaSource> keep, {
  required MangaSource? atsumaru,
}) {
  final out = [...keep];
  if (atsumaru != null && !out.any((s) => s.ref.id == atsumaru.ref.id)) {
    out.insert(out.length < maxTargets ? out.length : maxTargets - 1, atsumaru);
  }
  return out;
}

class _Hit {
  new(this.source, this.rank, this.manga, this.title, this.order);

  final MangaSource source;
  final int rank;
  final MangaSummary manga;
  final double title;
  final int order;
}

/// Finds the alternatives of library entries on [targets] (best first).
/// One finder is one session: searches, details and chapter lists are
/// cached per source and query (or url), failures included.
class CandidateFinder {
  /// Creates the finder; [timeout] bounds each request.
  new(this.targets, {this.timeout = const Duration(seconds: 15)});

  /// Target sources, best first ([migrationTargets]).
  final List<MangaSource> targets;

  /// Longest wait for one search, details or chapter list.
  final Duration timeout;

  /// Sources searched at once.
  static const concurrency = 2;

  final _searches = <String, Future<List<MangaSummary>>>{};
  final _details = <String, Future<MangaDetails?>>{};
  final _chapters = <String, Future<List<ChapterInfo>?>>{};

  /// The alternatives of [entry], whose own source is [own] (null when not
  /// installed) and whose progress is at [readChapter]. A [query] (manual
  /// search) replaces the title and alt titles as the only search.
  /// [onUpdate] hears a partial result each time a source's search ends
  /// (title-only scores, no chapter counts yet), before the final one.
  Future<EntryCandidates> find(
    LibraryEntry entry, {
    MangaSource? own,
    double? readChapter,
    String? query,
    void Function(EntryCandidates partial)? onUpdate,
  }) async {
    // In the background: the own source is often the slow or broken one,
    // and only alt-title searches and the final scores need it.
    final ownFacts = own == null
        ? Future.value((null, null))
        : (
            _detailsOf(own, entry.mangaUrl),
            _chaptersOf(own, entry.mangaUrl),
          ).wait;
    var wanted = MangaFacts(title: entry.title, readChapter: readChapter);
    if (query != null) wanted = wanted.withName(query);
    var match = SameManga(wanted);
    final picked = targets
        .where((s) => s.ref.id != entry.sourceId)
        .take(maxTargets)
        .toList();
    final states = List.filled(picked.length, LaneState.searching);
    final hits = <_Hit>[];
    List<Lane> lanes() => [
      for (var i = 0; i < picked.length; i++)
        (source: picked[i], state: states[i]),
    ];
    bool collect(int i, List<MangaSummary> found) {
      var good = false;
      for (final m in found) {
        final t = match.titleScore(MangaFacts(title: m.title));
        if (t < minTitleScore) continue;
        if (hits.any((h) => h.rank == i && h.manga.url == m.url)) continue;
        hits.add(_Hit(picked[i], i, m, t, hits.length));
        good |= t >= closeTitleScore;
      }
      return good;
    }

    await runPooled([for (var i = 0; i < picked.length; i++) i], concurrency, (
      i,
    ) async {
      final source = picked[i];
      try {
        if (!collect(i, await _search(source, query ?? entry.title)) &&
            query == null) {
          final (details, _) = await ownFacts;
          match = SameManga(wanted.withDetails(details));
          for (final alt in match.wanted.altTitles.take(maxAltQueries)) {
            if (collect(i, await _search(source, alt))) break;
          }
        }
        final any = hits.any((h) => h.rank == i);
        states[i] = any ? LaneState.found : LaneState.empty;
      } on Object {
        states[i] = LaneState.failed;
      }
      _sortHits(hits);
      onUpdate?.call(
        EntryCandidates(
          wanted: wanted,
          lanes: lanes(),
          best: [
            for (final h in hits.take(maxCandidates))
              MigrationCandidate(
                source: h.source,
                manga: h.manga,
                score: match.score(MangaFacts(title: h.manga.title)),
                rank: h.rank,
              ),
          ],
        ),
      );
    });
    final (ownDetails, ownChapters) = await ownFacts;
    wanted = wanted.withDetails(ownDetails, chapters: ownChapters?.length);
    match = SameManga(wanted);
    _sortHits(hits);
    final kept = hits.take(maxCandidates).toList();
    final best = List<MigrationCandidate?>.filled(kept.length, null);
    await runPooled([for (var j = 0; j < kept.length; j++) j], concurrency, (
      j,
    ) async {
      final h = kept[j];
      final details = j < detailedHits
          ? await _detailsOf(h.source, h.manga.url)
          : null;
      final chapters = await _chaptersOf(h.source, h.manga.url);
      best[j] = MigrationCandidate(
        source: h.source,
        manga: h.manga,
        score: match.score(
          MangaFacts(title: h.manga.title)
              .withDetails(details, chapters: chapters?.length),
        ),
        rank: h.rank,
        chapters: chapters?.length,
        newest: newestOf(chapters),
        description: details?.description,
        previewChapterUrl: firstOf(chapters)?.url,
      );
    });
    return EntryCandidates(
      wanted: wanted,
      lanes: lanes(),
      best: best.nonNulls.toList()..sort(MigrationCandidate.compare),
      ownChapters: ownChapters?.length,
      ownNewest: newestOf(ownChapters),
    );
  }

  static void _sortHits(List<_Hit> hits) => hits.sort((a, b) {
    final byTitle = b.title.compareTo(a.title);
    if (byTitle != 0) return byTitle;
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.order.compareTo(b.order);
  });

  static String _key(MangaSource s, String v) => '${s.ref.id}\u0000$v';

  Future<List<MangaSummary>> _search(MangaSource s, String q) =>
      _searches[_key(s, q)] ??= s
          .search(q, 1)
          .timeout(timeout)
          .then((p) => p.items);

  Future<MangaDetails?> _detailsOf(MangaSource s, String url) =>
      _details[_key(s, url)] ??= _orNull(s.details(url).timeout(timeout));

  Future<List<ChapterInfo>?> _chaptersOf(MangaSource s, String url) =>
      _chapters[_key(s, url)] ??= _orNull(s.chapters(url).timeout(timeout));

  static Future<T?> _orNull<T>(Future<T> f) async {
    try {
      return await f;
    } on Object {
      return null;
    }
  }
}
