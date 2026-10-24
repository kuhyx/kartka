import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';

import 'fakes.dart';

const _all = [
  'popular',
  'latest',
  'search',
  'manga_id',
  'manga_id_miss',
  'manga_id_unseen',
  'details',
  'details_unseen',
  'chapters',
  'chapter_id',
  'pages',
  'source_error',
];

const _info = SuwayomiSourceInfo(
  serverId: mangadexEn,
  ref: SourceRef(
    id: 'suwayomi:$mangadexEn',
    name: 'MangaDex',
    lang: 'en',
    origin: SourceOrigin.suwayomi,
  ),
  supportsLatest: true,
);

String _firstUrl(String name, [int i = 0]) {
  final r = fixture(name)['response']! as Map<String, Object?>;
  final data = r['data']! as Map<String, Object?>;
  final payload = data.values.first! as Map<String, Object?>;
  final list = payload.values.whereType<List<Object?>>().first;
  return (list[i]! as Map<String, Object?>)['url']! as String;
}

void main() {
  late FakeKartkaHttp http;
  SuwayomiSource source({
    SuwayomiSourceInfo info = _info,
    TitleLookup? titleOf,
  }) => SuwayomiSource(
    info: info,
    client: SuwayomiClient(http: http, settings: () => fixtureSettings),
    settings: () => fixtureSettings,
    titleOf: titleOf,
  );

  setUp(() => http = fixtureHttp(_all));

  test('popular maps summaries with absolute covers', () async {
    final page = await source().popular(1);
    expect(page.hasNext, isTrue);
    expect(page.items, hasLength(20));
    final first = page.items.first;
    expect(first.sourceId, 'suwayomi:$mangadexEn');
    expect(first.url, startsWith('/manga/'));
    expect(first.coverUrl, startsWith('http://127.0.0.1:4599/api/v1/manga/'));
  });

  test('latest and search page through the same mutation', () async {
    expect((await source().latest(1)).items, isNotEmpty);
    final found = await source().search('Sousou no Frieren', 1);
    expect(found.hasNext, isFalse);
    expect(found.items.map((m) => m.title), contains(contains('Frieren')));
  });

  test('latest is empty when the source has no latest listing', () async {
    final noLatest = SuwayomiSourceInfo(
      serverId: _info.serverId,
      ref: _info.ref,
      supportsLatest: false,
    );
    final page = await source(info: noLatest).latest(1);
    expect(page.items, isEmpty);
    expect(page.hasNext, isFalse);
    expect(bodies(http), isEmpty);
  });

  test('details resolves the server id by url, then fetches', () async {
    final url = _firstUrl('popular');
    final details = await source().details(url);
    expect(details.url, url);
    expect(details.authors, isNotEmpty);
    expect(details.description, isNotEmpty);
    expect(details.genres, isNotEmpty);
    expect(bodies(http).map((r) => r['operationName']), [
      'KartkaMangaId',
      'KartkaDetails',
    ]);
  });

  test('ids seen while browsing skip the lookup', () async {
    final s = source();
    await s.popular(1);
    await s.details(_firstUrl('popular'));
    expect(bodies(http).last['operationName'], 'KartkaDetails');
    expect(
      bodies(http).where((r) => r['operationName'] == 'KartkaMangaId'),
      isEmpty,
    );
  });

  test('chapters map numbers, dates and scanlators', () async {
    final chapters = await source().chapters(_firstUrl('popular'));
    expect(chapters, isNotEmpty);
    expect(chapters.first.number, isNotNull);
    expect(chapters.first.uploadedAt!.isUtc, isTrue);
    expect(chapters.first.scanlator, isNotNull);
    final numbers = [for (final c in chapters) c.number!];
    expect(
      numbers,
      orderedEquals([...numbers]..sort((a, b) => b.compareTo(a))),
    );
  });

  test('pages carry absolute urls and the basic-auth header', () async {
    final s = source();
    final chapters = await s.chapters(_firstUrl('popular'));
    final last = chapters.last; // oldest = the recorded chapter
    final pages = await s.pages(last.url);
    expect(pages, isNotEmpty);
    expect(pages.first.index, 0);
    expect(pages.first.imageUrl, startsWith('http://127.0.0.1:4599/api/v1/'));
    expect(pages.first.headers, fixtureSettings.authHeaders);
  });

  test('pages resolve a chapter id by url when not cached', () async {
    final pages = await source().pages(_firstUrl('chapters'));
    expect(pages, isNotEmpty);
    expect(bodies(http).first['operationName'], 'KartkaChapterId');
  });

  test('unknown chapter urls are not on the server', () async {
    http = fixtureHttp(_all);
    expect(
      () => source(info: _otherSource).pages(_firstUrl('chapters')),
      throwsA(isA<SuwayomiNotOnServerException>()),
    );
  });

  group('manga the server has never seen', () {
    const unseen = '/manga/b0b721ff-c388-4486-aa0f-c2b0bb321512';

    test('are found by a title search, then fetched', () async {
      final asked = <MangaKey>[];
      final details = await source(
        titleOf: (key) async {
          asked.add(key);
          return 'Sousou no Frieren';
        },
      ).details(unseen);
      expect(details.url, unseen);
      expect(asked, [mangaKeyOf('suwayomi:$mangadexEn', unseen)]);
      expect(bodies(http).map((r) => r['operationName']), [
        'KartkaMangaId',
        'KartkaSourceManga',
        'KartkaDetails',
      ]);
    });

    test('throw when there is no title to search', () async {
      expect(
        () => source(titleOf: (_) async => null).details(unseen),
        throwsA(
          isA<SuwayomiNotOnServerException>()
              .having((e) => e.url, 'url', unseen)
              .having((e) => e.sourceId, 'sourceId', 'suwayomi:$mangadexEn'),
        ),
      );
      expect(
        () => source().chapters(unseen),
        throwsA(isA<SuwayomiNotOnServerException>()),
      );
    });

    test('throw when the search has no exact url match', () async {
      expect(
        () =>
            source(titleOf: (_) async => 'Sousou no Frieren')
                .details('/manga/not-on-server'),
        throwsA(isA<SuwayomiNotOnServerException>()),
      );
    });
  });

  test('server errors surface as SuwayomiException', () async {
    final broken = SuwayomiSourceInfo(
      serverId: '1',
      ref: _info.ref,
      supportsLatest: true,
    );
    expect(
      () => source(info: broken).popular(1),
      throwsA(
        isA<SuwayomiException>().having(
          (e) => e.message,
          'message',
          contains('fetchSourceManga'),
        ),
      ),
    );
  });
}

const _otherSource = SuwayomiSourceInfo(
  serverId: '1411768577036936240',
  ref: SourceRef(
    id: 'suwayomi:1411768577036936240',
    name: 'MangaDex',
    lang: 'ja',
    origin: SourceOrigin.suwayomi,
  ),
  supportsLatest: true,
);
