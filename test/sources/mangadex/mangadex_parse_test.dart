import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/mangadex/mangadex_parse.dart';

import 'fixtures.dart';

void main() {
  final solo = fixtureObject('details.json')['data']! as Json;
  final soloAttrs = solo['attributes']! as Json;
  final feed = fixtureObject('feed_0.json')['data']! as List<Object?>;
  final ch3 = feed.first! as Json;

  group('pickTitle', () {
    test('romanized main title loses to an altTitle in the language', () {
      expect(pickTitle(soloAttrs, ['en']), 'Solo Leveling');
    });
    test('main title in the language wins over altTitles', () {
      expect(pickTitle(soloAttrs, ['ko-ro']), 'Na Honjaman Level-Up');
    });
    test('falls back to en, then to any title, then empty', () {
      expect(pickTitle(soloAttrs, ['xx']), 'Solo Leveling');
      expect(
        pickTitle(
          const {
            'title': {'ja-ro': 'Romaji'},
          },
          ['en'],
        ),
        'Romaji',
      );
      expect(pickTitle(const {}, ['en']), '');
    });
  });

  test('pickDescription uses the language, then en, else null', () {
    expect(pickDescription(soloAttrs, ['en']), startsWith('10 years ago'));
    expect(pickDescription(soloAttrs, ['fr']), isNot(startsWith('10 years')));
    expect(pickDescription(soloAttrs, ['xx']), startsWith('10 years ago'));
    expect(
      pickDescription(const {'description': <String, Object?>{}}, ['en']),
      isNull,
    );
    expect(
      pickDescription(
        const {
          'description': {'en': '  '},
        },
        ['en'],
      ),
      isNull,
    );
  });

  test('trackerIds maps al, mal and mu only', () {
    expect(trackerIds(soloAttrs), {
      'anilist': '105398',
      'mal': '121496',
      'mangaupdates': '6z1uqw7',
    });
    expect(
      trackerIds(const {
        'links': {'mu': 'abc', 'raw': 'x'},
      }),
      {'mangaupdates': 'abc'},
    );
    expect(trackerIds(const {'links': null}), isEmpty);
    expect(trackerIds(const {}), isEmpty);
  });

  test('relationship names keep order and drop duplicates', () {
    expect(relNames(solo, 'author'), [
      'h-goon (현군)',
      'Chugong (추공)',
      'Gi So-Ryeong (기소령)',
    ]);
    expect(relNames(solo, 'artist'), hasLength(2));
    expect(relNames(const {}, 'author'), isEmpty);
  });

  test('coverFile reads the cover_art relationship', () {
    expect(coverFile(solo), 'e90bdc47-c8b9-4df7-b2c0-17641b645ee1.jpg');
    expect(
      coverFile(const {
        'relationships': [
          {'type': 'cover_art', 'id': 'x'},
        ],
      }),
      isNull,
    );
    expect(coverFile(const {}), isNull);
  });

  test('tagNames uses English tag names', () {
    expect(tagNames(soloAttrs), containsAll(['Action', 'Long Strip']));
    expect(tagNames(const {}), isEmpty);
  });

  group('chapters', () {
    test('recorded chapter with title and two groups', () {
      final attrs = ch3['attributes']! as Json;
      expect(chapterName(attrs), 'Ch. 3 - The Ice Prince Is Dead!');
      expect(chapterNumber(attrs), 3);
      expect(scanlator(ch3), "KukoriScans & Scribe's Chamber");
      expect(publishedAt(attrs), DateTime.utc(2026, 9, 6, 14, 57, 38));
    });
    test('volume, decimal numbers, oneshots and missing titles', () {
      expect(
        chapterName(const {'volume': '2', 'chapter': '10.5', 'title': ''}),
        'Vol. 2 Ch. 10.5',
      );
      expect(chapterNumber(const {'chapter': '10.5'}), 10.5);
      expect(chapterName(const {'title': 'Extra'}), 'Extra');
      expect(chapterName(const {}), 'Oneshot');
      expect(chapterNumber(const {'chapter': null}), isNull);
      expect(chapterNumber(const {'chapter': 'x'}), isNull);
      expect(publishedAt(const {}), isNull);
      expect(scanlator(const {'relationships': <Object?>[]}), isNull);
    });
  });

  test('apiError reads the first error, or a generic message', () {
    final err = fixtureObject('error_404.json');
    expect(apiError(err), contains('not found'));
    expect(apiError(const {}), 'MangaDex error');
  });
}
