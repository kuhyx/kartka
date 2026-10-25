import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/search_text.dart';

import 'fixtures.dart';

List<String> ids(List<SourceHealthRecord> rs) => [for (final r in rs) r.id];

SourceHealthRecord rec(Map<String, Object?> json) =>
    SourceHealthRecord.fromJson(json)!;

final SourceHealthRecord _webview = rec(const {
  'id': 'web',
  'name': 'Webby',
  'verdict': 'keep',
  'score': 0.95,
  'blocking': {
    'challengeRate': 0.2,
    'kinds': ['webview'],
  },
  'flags': ['needs-browser-engine'],
  'imageQuality': {'medianWidthPx': 1500},
  'pagesLoad': {'ratio': 0.92, 'sampled': 25},
  'langScope': 'en+ja',
  'cutReasons': ['coverage<0.60'],
});

final SourceHealthRecord _exactScore = rec(const {
  'id': 'e',
  'name': 'Edge',
  'score': 0.85,
});

void main() {
  final all = fixtureRecords();
  List<String> search(String q, {HealthQuery base = const HealthQuery()}) =>
      ids(base.copyWith(search: q).apply([...all, _webview]));

  group('search', () {
    test('empty query is the current behaviour', () {
      expect(search(''), ids(const HealthQuery().apply([...all, _webview])));
      expect(search('   '), search(''));
    });

    test('typos find MangaDex; ties keep the current sort', () {
      expect(search('mangdex'), ['mangadex', 'suwayomi:2499283573021220255']);
      const worst = HealthQuery(reversed: true);
      // Exact name matches tie, so the reversed sort orders them; the
      // two-letter-off Mangarden trails both.
      expect(search('mangadex', base: worst), [
        'suwayomi:2499283573021220255',
        'mangadex',
        'suwayomi:7034581279101437511',
      ]);
    });

    test('ranks by match quality before the sort', () {
      expect(search('local').first, 'local');
      expect(search('comick').first, 'plugin:comick');
    });

    test('matches metrics, reasons, kinds, origin and new fields', () {
      expect(search('cloudflare'), ['plugin:comick']);
      expect(search('#5'), ['plugin:comick']);
      expect(search('p95'), hasLength(6));
      expect(search('1500 px'), ['web']);
      expect(search('redundant'), ['suwayomi:2499283573021220255']);
      expect(search('coverage<0.60'), contains('suwayomi:1111'));
      expect(search('catalogue too small'), contains('plugin:comick'));
      expect(search('too many requests'), ['plugin:comick']);
      expect(search('browser engine').first, 'web');
      expect(search('en+ja'), ['web']);
      expect(search('92 %'), contains('web'));
      expect(search('pending'), contains('suwayomi:7034581279101437511'));
      expect(search('suwayomi'), contains('suwayomi:1111'));
      expect(search('js plugin'), contains('plugin:comick'));
      expect(search('polski zzzz'), isEmpty);
    });

    test('subset target is searchable by name', () {
      final text = searchTextOf(all[1], nameOf: (id) => 'Covering $id');
      expect(text.secondary, contains('Covering mangadex'));
      expect(text.primary, ['MangaDex', 'suwayomi:2499283573021220255']);
    });

    test('search text carries pagesLoad, langScope and flags', () {
      final text = searchTextOf(_webview).secondary;
      expect(text, containsAll(['92 % of 25 sampled', 'en+ja']));
      expect(text, containsAll(['needs-browser-engine', 'Browser engine']));
      expect(text, contains('tested EN + JA only'));
      expect(langScopeLabel('unrestricted'), 'tested all languages');
      expect(langScopeLabel('ko'), 'tested ko');
    });
  });

  group('reason filter', () {
    test('maps cut reasons, subsetOf, blocking kinds and the flag', () {
      expect(reasonsOf(all[2]), {
        HealthReason.uptime,
        HealthReason.blocking,
        HealthReason.coverage,
      });
      expect(reasonsOf(all[1]), {HealthReason.subset});
      expect(reasonsOf(_webview), {
        HealthReason.browserEngine,
        HealthReason.coverage,
      });
      expect(reasonsOf(all[0]), isEmpty);
      expect(
        reasonsOf(
          rec(const {
            'id': 'k',
            'blocking': {
              'kinds': ['403', 'webview'],
            },
          }),
        ),
        {HealthReason.blocking, HealthReason.browserEngine},
      );
      for (final r in HealthReason.values) {
        expect(r.label, isNotEmpty);
      }
    });

    test('any selected reason matches; ANDed with other filters', () {
      HealthQuery q(Set<HealthReason> rs) => HealthQuery(reasons: rs);
      final both = [...all, _webview];
      expect(ids(q({HealthReason.coverage}).apply(all)), [
        'suwayomi:1111',
        'plugin:comick',
      ]);
      expect(ids(q({HealthReason.subset, HealthReason.uptime}).apply(all)), [
        'suwayomi:2499283573021220255',
        'plugin:comick',
      ]);
      expect(ids(q({HealthReason.browserEngine}).apply(both)), ['web']);
      expect(
        ids(
          q({HealthReason.coverage})
              .copyWith(verdicts: {HealthVerdict.keep})
              .apply(both),
        ),
        ['web'],
      );
    });
  });

  group('minimum score', () {
    test('drops lower and unscored records; 0 keeps everything', () {
      const q = HealthQuery(minScore: 0.85);
      expect(ids(q.apply(all)), ['mangadex', 'local']);
      expect(const HealthQuery().apply(all), hasLength(6));
    });

    test('slider steps compare with float slack', () {
      const q = HealthQuery(minScore: 17 * 0.05);
      expect(ids(q.apply([_exactScore])), ['e']);
    });

    test('combines with search', () {
      const q = HealthQuery(minScore: 0.9, search: 'mangadex');
      expect(ids(q.apply(all)), ['mangadex']);
    });
  });

  test('copyWith keeps and replaces the new fields', () {
    const q = HealthQuery(
      search: 's',
      reasons: {HealthReason.subset},
      minScore: 0.5,
    );
    final same = q.copyWith(reversed: true);
    expect((same.search, same.minScore), ('s', 0.5));
    expect(same.reasons, {HealthReason.subset});
    final other = q.copyWith(search: 't', reasons: {}, minScore: 0.1);
    expect((other.search, other.minScore), ('t', 0.1));
    expect(other.reasons, isEmpty);
  });
}
