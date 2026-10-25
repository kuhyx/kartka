import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/source_ref.dart';

SourceRef _src(
  String id,
  String lang, [
  SourceOrigin o = SourceOrigin.native,
]) => SourceRef(id: id, name: id, lang: lang, origin: o);

void main() {
  test('buckets lower-case, fold all/multi together, keep regions', () {
    expect(languageBucket('EN'), 'en');
    expect(languageBucket(' multi '), kAllLanguages);
    expect(languageBucket('all'), kAllLanguages);
    expect(languageBucket('pt-BR'), 'pt-br');
  });

  test('labels known codes and upper-cases unknown ones', () {
    expect(languageLabel('en'), 'English');
    expect(languageLabel(kAllLanguages), 'All languages');
    expect(languageLabel('xx'), 'XX');
  });

  test('the default selection is en, then all/multi, then ja', () {
    expect(kDefaultBrowseLanguages, ['en', kAllLanguages, 'ja']);
  });

  final en = _src('en1', 'en');
  final multi = _src('m1', 'multi', SourceOrigin.suwayomi);
  final all = _src('a1', 'all');
  final ja = _src('j1', 'ja');
  final pl = _src('p1', 'pl');

  test('default selection shows only en, all/multi, ja in that order', () {
    final sections = sectionSources(
      [pl, ja, multi, all, en],
      const {},
      kDefaultBrowseLanguages,
    );
    expect(sections.map((s) => s.language), ['en', kAllLanguages, 'ja']);
    final allIds = [
      for (final g in sections[1].groups)
        for (final s in g.sources) s.id,
    ];
    expect(allIds, ['a1', 'm1']); // Built-in group before Suwayomi.
  });

  test('sections follow selected-language order, then origin, then rank', () {
    final enPlugin = _src('en2', 'en', SourceOrigin.plugin);
    final enSuwa = _src('en3', 'en', SourceOrigin.suwayomi);
    final enSuwaTop = _src('en4', 'en', SourceOrigin.suwayomi);
    const keep = HealthVerdict.keep;
    final sections = sectionSources(
      [enPlugin, enSuwa, enSuwaTop, en, pl],
      {
        'en4': const SourceHealthSummary(rank: 1, verdict: keep),
        'en3': const SourceHealthSummary(rank: 2, verdict: keep),
      },
      ['pl', 'en'],
    );
    expect(sections.map((s) => s.language), ['pl', 'en']);
    expect(sections[1].groups.map((g) => g.origin), [
      SourceOrigin.native,
      SourceOrigin.suwayomi,
      SourceOrigin.plugin,
    ]);
    expect(sections[1].groups[1].sources.map((s) => s.id), ['en4', 'en3']);
  });

  test('a selected language with no sources yields no section', () {
    expect(sectionSources([en], const {}, ['ja', 'en']).single.language, 'en');
  });

  test('empty selection hides everything', () {
    expect(sectionSources([en, ja], const {}, const []), isEmpty);
  });

  test('counts sources per bucket', () {
    expect(languageCounts([en, multi, all, ja, _src('j2', 'JA')]), {
      'en': 1,
      kAllLanguages: 2,
      'ja': 2,
    });
  });

  test('picker lists selected present languages first, then the rest', () {
    final counts = {'pl': 1, 'en': 2, 'ko': 1, 'ja': 3, kAllLanguages: 1};
    expect(pickerLanguages(counts, ['ja', 'fr', 'en']), [
      'ja',
      'en',
      kAllLanguages,
      'ko',
      'pl',
    ]);
  });
}
