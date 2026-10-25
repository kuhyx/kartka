/// A small fuzzy matcher for the Sources search box: case- and
/// diacritic-insensitive, tolerant of skipped letters and small typos.
///
/// Matching works per field and per word, never across the concatenated
/// text: a subsequence over a whole record would let short queries match
/// almost anything spread over its long cut-reason sentences.
library;

import 'dart:math' as math;

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ą': 'a', //
  'ă': 'a', 'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ę': 'e', 'ě': 'e', 'ğ': 'g',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i', 'ł': 'l', 'ľ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ö': 'o', 'ø': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's',
  'ş': 's', 'ß': 'ss', 'ť': 't', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ů': 'u', 'ű': 'u', 'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
};

/// [text] lower-cased with diacritics removed (`Łódź` → `lodz`). Dart has
/// no Unicode decomposition, so precomposed letters map through a table and
/// stray combining marks are dropped.
String foldForSearch(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final c = String.fromCharCode(rune);
    out.write(_fold[c] ?? c);
  }
  return out.toString();
}

final _word = RegExp('[a-z0-9]+');
final _letters = RegExp(r'^[a-z]+$');

/// Match quality tiers, best first.
const double _exact = 1;
const double _fieldPrefix = 0.95;
const double _wordPrefix = 0.9;
const double _inner = 0.8;
const double _compact = 0.75;

/// Weight of a secondary field against the name and id.
const double secondaryWeight = 0.9;

/// A parsed search query; every whitespace-separated token must match.
class FuzzyQuery {
  /// Parses [query].
  new(String query)
    : _phrase = foldForSearch(query.trim()),
      _tokens = foldForSearch(query)
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

  final String _phrase;
  final List<String> _tokens;

  /// True for a blank query, which matches everything.
  bool get isEmpty => _tokens.isEmpty;

  /// How well the query matches a record whose [primary] fields (name, id)
  /// and [secondary] fields (everything else) are given; null when some
  /// token matches nothing. Scores lie in (0, 1].
  double? score(List<String> primary, List<String> secondary) {
    if (isEmpty) return 1;
    final p = [for (final f in primary) foldForSearch(f)];
    final s = [for (final f in secondary) foldForSearch(f)];
    double best(String token, double Function(String, String) tier) => math.max(
      _max(p, (f) => tier(token, f)),
      secondaryWeight * _max(s, (f) => tier(token, f)),
    );
    var total = 0.0;
    for (final t in _tokens) {
      final v = best(t, _tokenTier);
      if (v == 0) return null;
      total += v;
    }
    final phrase = _tokens.length > 1 ? best(_phrase, _substringTier) : 0.0;
    return math.max(total / _tokens.length, phrase);
  }
}

double _max(List<String> fields, double Function(String) f) =>
    fields.fold(0, (m, field) => math.max(m, f(field)));

double _substringTier(String q, String field) {
  if (field == q) return _exact;
  final at = field.indexOf(q);
  if (at < 0) return 0;
  if (at == 0) return _fieldPrefix;
  for (var i = at; i >= 0; i = field.indexOf(q, i + 1)) {
    if (_wordStart(field, i)) return _wordPrefix;
  }
  return _inner;
}

bool _wordStart(String field, int at) =>
    at == 0 || !_word.hasMatch(field[at - 1]);

double _tokenTier(String token, String field) {
  final sub = _substringTier(token, field);
  if (sub > 0) return sub;
  if (token.length >= 4 &&
      field.replaceAll(RegExp('[^a-z0-9]'), '').contains(token)) {
    return _compact;
  }
  // Short or non-word tokens (`p95`, `1500`, `en+ja`) must match as
  // written: one letter of slack there turns p95 into p50.
  if (token.length < 4 || !_letters.hasMatch(token)) return 0;
  var best = 0.0;
  for (final m in _word.allMatches(field)) {
    best = math.max(best, _wordTier(token, m[0]!));
  }
  return best;
}

/// Subsequence within one word, or a typo against the word or its prefix.
double _wordTier(String token, String word) {
  var best = 0.0;
  if (word.length <= 2 * token.length && _isSubsequence(token, word)) {
    best = 0.6 + 0.1 * token.length / word.length;
  }
  final allowed = token.length >= 8 ? 2 : 1;
  final head = word.substring(0, math.min(word.length, token.length));
  final d = math.min(_osa(token, word), _osa(token, head));
  if (d <= allowed) best = math.max(best, 0.5 - 0.1 * (d - 1));
  return best;
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
  }
  return i == needle.length;
}

/// Optimal-string-alignment distance (Levenshtein plus adjacent swaps).
int _osa(String a, String b) {
  final rows = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1);
      v = math.min(v, rows[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, rows[i - 2][j - 2] + 1);
      }
      rows[i][j] = v;
    }
  }
  return rows[a.length][b.length];
}
