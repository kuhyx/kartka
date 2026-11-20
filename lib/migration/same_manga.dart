/// Whether a search hit is the same series as a wanted manga: pure, with
/// no UI or source dependency, so duplicate merging can reuse it.
///
/// [SameManga.score] is a weighted mean in [0, 1] of four signals, an
/// unknown one counting as a neutral 0.5:
///
/// - title (weight [titleWeight]): the best [titleSimilarity] between any
///   name of the wanted manga and any name of the hit;
/// - authors (0.2): 1 when some author's name is the same (word order and
///   case aside), 0 when both list authors and none agree;
/// - description (0.25): the overlap coefficient of their content words
///   (|A ∩ B| / min(|A|, |B|), so one source's longer blurb does not dilute
///   it), mapped from 0.15 → 0 to 0.5 → 1;
/// - chapters (0.1): the smaller over the larger count, 0.5 or more being
///   plausible (1); against what kuhy has read when the wanted count is
///   unknown.
///
/// So a hit with the right title whose author and description disagree
/// scores 0.55, below an unchecked hit with that title (0.725), and the
/// real one scores near 1.
library;

import 'dart:math' as math;

import 'package:kartka/migration/manga_facts.dart';
import 'package:kartka/source_health/fuzzy_match.dart';

export 'package:kartka/migration/manga_facts.dart';

/// Weight of the title in [SameManga.score].
const double titleWeight = 0.45;
const double _authorWeight = 0.2;
const double _descriptionWeight = 0.25;
const double _chapterWeight = 0.1;
const double _unknown = 0.5;

/// A score from which a hit is shown as a strong match.
const double strongMatch = 0.8;

/// A score from which a hit is shown as a fair match.
const double fairMatch = 0.6;

/// Lowest fuzzy score, in both directions, of a close title match.
const double closeTitleScore = 0.7;

final _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _words(String title) =>
    title.replaceAll('&', ' and ').replaceAll(_punctuation, ' ').trim();

/// How alike titles [a] and [b] are: the Sources search's fuzzy score of
/// each as a query against the other, the lower one (so a title only
/// contained in a longer one does not count); 0 when either misses.
double titleSimilarity(String a, String b) {
  final x = _words(a);
  final y = _words(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final there = FuzzyQuery(x).score([y], const []) ?? 0;
  final back = FuzzyQuery(y).score([x], const []) ?? 0;
  return math.min(there, back);
}

/// Scores hits against [wanted].
class SameManga {
  /// A matcher for [wanted].
  const new(this.wanted);

  /// The manga looked for.
  final MangaFacts wanted;

  /// The best similarity between a name of [wanted] and one of [hit].
  double titleScore(MangaFacts hit) {
    var best = 0.0;
    for (final a in wanted.names) {
      for (final b in hit.names) {
        best = math.max(best, titleSimilarity(a, b));
      }
    }
    return best;
  }

  /// 1 when an author agrees, 0 when none does; null when either has none.
  double? authorScore(MangaFacts hit) {
    final a = wanted.authors.map(_nameWords).where((w) => w.isNotEmpty);
    final b = hit.authors.map(_nameWords).where((w) => w.isNotEmpty).toList();
    if (a.isEmpty || b.isEmpty) return null;
    for (final x in a) {
      for (final y in b) {
        if (x.containsAll(y) || y.containsAll(x)) return 1;
      }
    }
    return 0;
  }

  /// The mapped word overlap of the descriptions; null when either has
  /// fewer than [_minWords] content words.
  double? descriptionScore(MangaFacts hit) {
    final a = _contentWords(wanted.description);
    final b = _contentWords(hit.description);
    if (a.length < _minWords || b.length < _minWords) return null;
    final overlap = a.intersection(b).length / math.min(a.length, b.length);
    return ((overlap - 0.15) / 0.35).clamp(0, 1).toDouble();
  }

  /// How plausible the hit's chapter count is; null when unknown.
  double? chapterScore(MangaFacts hit) {
    final count = hit.chapters;
    if (count == null) return null;
    if (count == 0) return 0;
    if (wanted.chapters case final n? when n > 0) {
      return (math.min(n, count) / math.max(n, count) / 0.5).clamp(0, 1);
    }
    if (wanted.readChapter case final read? when read > 0) {
      return (count / read).clamp(0, 1).toDouble();
    }
    return null;
  }

  /// How sure it is that [hit] is [wanted], in [0, 1].
  double score(MangaFacts hit) =>
      titleWeight * titleScore(hit) +
      _authorWeight * (authorScore(hit) ?? _unknown) +
      _descriptionWeight * (descriptionScore(hit) ?? _unknown) +
      _chapterWeight * (chapterScore(hit) ?? _unknown);
}

const _minWords = 6;

Set<String> _nameWords(String name) =>
    foldForSearch(name)
        .split(RegExp('[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toSet();

const _stop = {
  'the', 'and', 'for', 'with', 'who', 'whom', 'his', 'her', 'their', 'they', //
  'she', 'him', 'them', 'that', 'this', 'from', 'into', 'are', 'was', 'were',
  'has', 'have', 'had', 'but', 'not', 'can', 'will', 'one', 'all', 'its',
  'out', 'when', 'what', 'which', 'there', 'then', 'than', 'been', 'also',
  'read', 'online', 'manga', 'chapter', 'chapters', 'free',
};

Set<String> _contentWords(String? text) => {
  if (text != null)
    for (final w in foldForSearch(text).split(RegExp('[^a-z0-9]+')))
      if (w.length >= 3 && !_stop.contains(w)) w,
};
