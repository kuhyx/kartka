import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_urls.dart';

void main() {
  const urls = MangadexUrls(MangadexSettings.defaults);
  const id = 'aa6c76f7-5f5f-46b6-a800-911145f81b9b';

  void expectBrowse(Uri u, {required int offset}) {
    final q = u.queryParametersAll;
    expect(u.scheme, 'https');
    expect(u.host, 'api.mangadex.org');
    expect(u.path, '/manga');
    expect(q['limit'], ['20']);
    expect(q['offset'], ['$offset']);
    expect(q['includes[]'], ['cover_art']);
    expect(q['contentRating[]'], ['safe', 'suggestive']);
    expect(q['availableTranslatedLanguage[]'], ['en']);
  }

  test('popular orders by follows and pages by 20 (1-based)', () {
    final u = urls.popular(2);
    expectBrowse(u, offset: 20);
    expect(u.queryParameters['order[followedCount]'], 'desc');
    expect(u.queryParameters['hasAvailableChapters'], 'true');
  });

  test('latest orders by latest uploaded chapter', () {
    final u = urls.latest(1);
    expectBrowse(u, offset: 0);
    expect(u.queryParameters['order[latestUploadedChapter]'], 'desc');
  });

  test('search sends the title and relevance order', () {
    final u = urls.search('yotsuba', 3);
    expectBrowse(u, offset: 40);
    expect(u.queryParameters['title'], 'yotsuba');
    expect(u.queryParameters['order[relevance]'], 'desc');
  });

  test('page numbers below 1 are clamped to the first page', () {
    expect(urls.popular(0).queryParameters['offset'], '0');
  });

  test('settings drive languages and ratings', () {
    const custom = MangadexUrls(
      MangadexSettings(
        languages: ['pl', 'en'],
        dataSaver: true,
        ratings: {ContentRating.erotica},
      ),
    );
    final q = custom.popular(1).queryParametersAll;
    expect(q['availableTranslatedLanguage[]'], ['pl', 'en']);
    expect(q['contentRating[]'], ['erotica']);
    expect(
      custom.feed(id, offset: 0).queryParametersAll['translatedLanguage[]'],
      ['pl', 'en'],
    );
  });

  test('details includes cover, author and artist', () {
    final u = urls.details(id);
    expect(u.path, '/manga/$id');
    expect(u.queryParametersAll['includes[]'], [
      'cover_art',
      'author',
      'artist',
    ]);
  });

  test('feed asks every rating, no external or empty chapters', () {
    final u = urls.feed(id, offset: 500);
    final q = u.queryParametersAll;
    expect(u.path, '/manga/$id/feed');
    expect(q['limit'], ['500']);
    expect(q['offset'], ['500']);
    expect(q['contentRating[]'], [
      'safe',
      'suggestive',
      'erotica',
      'pornographic',
    ]);
    expect(q['includes[]'], ['scanlation_group']);
    expect(q['includeExternalUrl'], ['0']);
    expect(q['includeEmptyPages'], ['0']);
    expect(q['includeFuturePublishAt'], ['0']);
    expect(q['order[volume]'], ['desc']);
    expect(q['order[chapter]'], ['desc']);
    expect(urls.feed(id, offset: 0, limit: 3).queryParameters['limit'], '3');
  });

  test('at-home server and page image urls', () {
    expect(
      urls.atHome('c1').toString(),
      'https://api.mangadex.org/at-home/server/c1',
    );
    expect(
      MangadexUrls.pageImage('https://x.mangadex.network', 'h', 'f.jpg'),
      'https://x.mangadex.network/data/h/f.jpg',
    );
    expect(
      MangadexUrls.pageImage(
        'https://x.mangadex.network',
        'h',
        'f.jpg',
        dataSaver: true,
      ),
      'https://x.mangadex.network/data-saver/h/f.jpg',
    );
  });

  test('cover thumbnail on uploads.mangadex.org', () {
    expect(
      MangadexUrls.cover(id, 'c.jpg'),
      'https://uploads.mangadex.org/covers/$id/c.jpg.512.jpg',
    );
  });

  test('ids round-trip through Keiyoushi-compatible urls', () {
    expect(MangadexUrls.mangaUrl(id), '/manga/$id');
    expect(MangadexUrls.chapterUrl('c1'), '/chapter/c1');
    expect(MangadexUrls.idOf('/manga/$id'), id);
    expect(MangadexUrls.idOf('/chapter/c1'), 'c1');
    expect(MangadexUrls.idOf('https://mangadex.org/title/$id/slug'), id);
    expect(MangadexUrls.idOf(id), id);
    expect(() => MangadexUrls.idOf('/manga/'), throwsFormatException);
  });
}
