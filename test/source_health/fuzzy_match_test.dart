import 'package:glados/glados.dart';
import 'package:kartka/source_health/fuzzy_match.dart';

double? score(
  String q,
  List<String> primary, [
  List<String> other = const [],
]) => FuzzyQuery(q).score(primary, other);

const _alphabet = 'abcelnoszAĄĆĘŁŃÓŚŹŻąćęłńóśźżéüß0159';

extension on Any {
  Generator<String> get word =>
      nonEmptyList(choose(_alphabet.split(''))).map((cs) => cs.join());
}

void main() {
  group('foldForSearch', () {
    test('lower-cases and strips diacritics, Polish included', () {
      expect(foldForSearch('Łódź ŻÓŁĆ Ąę ŚŃ'), 'lodz zolc ae sn');
      expect(foldForSearch('Crème Brûlée Straße'), 'creme brulee strasse');
      expect(foldForSearch('Café'), 'cafe');
    });
  });

  group('FuzzyQuery', () {
    test('empty or blank query matches everything at full score', () {
      expect(FuzzyQuery('  ').isEmpty, isTrue);
      expect(score('', ['x']), 1);
      expect(FuzzyQuery('a').isEmpty, isFalse);
    });

    test('tolerates subsequences and small typos', () {
      expect(score('mangdex', ['MangaDex']), isNotNull);
      expect(score('mnagadex', ['MangaDex']), isNotNull);
      expect(score('mangadxe', ['MangaDex']), isNotNull);
      expect(score('mngadx', ['MangaDex']), isNotNull);
      expect(score('mnaga', ['MangaDex']), isNotNull);
      expect(score('tinyscans', ['Tiny Scans']), isNotNull);
    });

    test('finds rendered metric text and codes', () {
      expect(score('cloudflare', ['35 % (Cloudflare challenge)']), isNotNull);
      expect(score('p95', ['p50 420 ms · p95 1.3 s']), isNotNull);
      expect(score('1500 px', ['1500 px']), 1);
      expect(score('coverage<0.60', ['coverage<0.60']), 1);
      expect(score('en+ja', ['en+ja']), 1);
    });

    test('every token must match some field', () {
      expect(
        score('mangadex cloudflare', ['MangaDex'], ['Cloudflare']),
        isNotNull,
      );
      expect(score('mangadex zzzz', ['MangaDex'], ['Cloudflare']), isNull);
      expect(score('xyzzy', ['MangaDex', 'mangadex', 'keep']), isNull);
    });

    test('short and numeric tokens need a substring', () {
      expect(score('ab', ['ac']), isNull);
      expect(score('cut', ['count']), isNull);
      expect(score('pl', ['Polish', 'pl']), 1);
      expect(score('dex', ['MangaDex']), isNotNull);
      expect(score('1500', ['1100 px']), isNull);
      expect(score('p95', ['p50 420 ms']), isNull);
      expect(score('1500 px', ['1500 px']), 1);
    });

    test('ranks exact > prefix > word prefix > inner > subsequence > typo', () {
      final scores = [
        score('manga', ['Manga']),
        score('manga', ['Mangadex']),
        score('manga', ['Read manga here']),
        score('manga', ['Tomangar']),
        score('manga', ['mangoa']),
        score('manga', ['mxnga']),
      ];
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], lessThan(scores[i - 1]!), reason: 'tier $i');
      }
    });

    test('secondary fields weigh less than the name', () {
      expect(
        score('comick', ['Comick']),
        greaterThan(score('comick', ['x'], ['Comick'])!),
      );
    });
  });

  group('properties', () {
    Glados2(any.word, any.word).test('case and diacritics never matter', (
      a,
      b,
    ) {
      final field = '$a $b';
      expect(
        score(a.toUpperCase(), [field]),
        score(foldForSearch(a), [foldForSearch(field)]),
      );
    });

    Glados3(any.word, any.positiveIntOrZero, any.positiveIntOrZero).test(
      'any substring of a field matches, scoring in (0, 1]',
      (w, x, y) {
        final folded = foldForSearch(w);
        final start = x % folded.length;
        final end = start + 1 + y % (folded.length - start);
        final s = score(folded.substring(start, end), ['zz $w']);
        expect(s, isNotNull);
        expect(s, inExclusiveRange(0, 1.0001));
      },
    );

    Glados2(any.word, any.positiveIntOrZero).test(
      'dropping one letter of a 5+ letter word still matches',
      (w, i) {
        final folded = foldForSearch(w);
        if (folded.length < 5 || folded.contains(RegExp('[0-9]'))) return;
        final at = i % folded.length;
        final q = folded.substring(0, at) + folded.substring(at + 1);
        expect(score(q, [w]), isNotNull);
      },
    );

    Glados(any.word).test('an exact field outranks any other field', (w) {
      final exact = score(w, [w])!;
      expect(exact, 1);
      expect(score(w, ['zz${w}zz']) ?? 0, lessThan(exact));
    });
  });
}
