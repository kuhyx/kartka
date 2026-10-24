import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/anilist/anilist_parse.dart';
import 'package:kartka/tracking/common/tracker.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(
          File('test/fixtures/tracking-anilist/$name.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  group('parseSearch', () {
    test('maps the recorded Yotsuba search', () {
      final hits = parseSearch(fixture('search_yotsuba'));
      expect(hits, hasLength(5));
      expect(
        hits.first,
        const TrackSearchResult(
          remoteId: '30104',
          title: 'Yotsuba to!',
          coverUrl:
              'https://s4.anilist.co/file/anilistcdn/media/manga/cover/medium/bx30104-sUVzNlTWZ5cu.jpg',
        ),
      );
      expect(hits[1].chapters, 1);
    });

    test('empty page gives no hits', () {
      expect(parseSearch(fixture('search_empty')), isEmpty);
    });

    test('falls back to english, then romaji, then the id', () {
      Map<String, Object?> page(Map<String, Object?> title) => {
        'data': {
          'Page': {
            'media': [
              {'id': 7, 'title': title, 'coverImage': null},
            ],
          },
        },
      };
      expect(parseSearch(page({'english': 'E', 'romaji': 'R'})).single.title,
          'E');
      expect(parseSearch(page({'romaji': 'R'})).single.title, 'R');
      expect(parseSearch(page({})).single.title, '7');
    });
  });

  group('parseFetch', () {
    test('no list entry is null', () {
      expect(parseFetch(fixture('fetch_no_entry')), isNull);
    });

    test('maps an in-progress entry', () {
      expect(
        parseFetch(fixture('fetch_entry')),
        const TrackStatus(
          remoteId: '30104',
          chaptersRead: 42,
          status: 'CURRENT',
          score: 8.5,
        ),
      );
    });

    test('score 0 means unscored', () {
      final s = parseFetch(fixture('fetch_completed'))!;
      expect(s.score, isNull);
      expect(s.totalChapters, 1);
      expect(s.status, 'COMPLETED');
    });

    test('missing Media is null', () {
      expect(parseFetch({'data': {'Media': null}}), isNull);
    });
  });

  test('parseSaved reads the stored progress', () {
    expect(parseSaved(fixture('save_entry')), 43);
  });

  group('errors', () {
    test('invalid token is an auth error', () {
      expect(
        () => parseSearch(fixture('invalid_token')),
        throwsA(
          isA<AniListException>()
              .having((e) => e.isAuthError, 'auth', isTrue)
              .having((e) => e.status, 'status', 400),
        ),
      );
    });

    test('429 is a rate-limit error, not auth', () {
      expect(
        () => parseFetch(fixture('rate_limited')),
        throwsA(
          isA<AniListException>()
              .having((e) => e.isRateLimited, 'rate', isTrue)
              .having((e) => e.isAuthError, 'auth', isFalse)
              .having((e) => e.toString(), 'text', contains('Too Many')),
        ),
      );
    });

    test('a non-map body is malformed', () {
      expect(() => parseSaved({'data': 3}), throwsA(isA<AniListException>()));
      expect(
        () => parseSaved({'errors': 'x'}),
        throwsA(isA<AniListException>()),
      );
    });

    test('error without status or message still throws', () {
      expect(
        () => parseSaved({
          'errors': [<String, Object?>{}],
        }),
        throwsA(
          isA<AniListException>().having((e) => e.status, 'status', isNull),
        ),
      );
    });

    test('401 is an auth error', () {
      const e = AniListException('Unauthorized', status: 401);
      expect(e.isAuthError, isTrue);
    });
  });
}
