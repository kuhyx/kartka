import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/legacy_urls.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';

import 'fakes.dart';

// Real shapes (live server, 2026-10-29): the library keeps the old
// allanime extension's URLs, the server only knows the current ones.
const _legacyManga = '/manga/LHBPxBgNFD26rwgFC/boku-no-tsuma-wa-kanjou-ga-nai';
const _legacyChapter =
    '/read/LHBPxBgNFD26rwgFC/boku-no-tsuma-wa-kanjou-ga-nai/chapter-55-sub';
const _unseen = '/manga/ZqnzvAw2qzQBnZ6WP/mimi';

SourceRef _ref(String serverId) => SourceRef(
  id: 'suwayomi:$serverId',
  name: 'AllManga',
  lang: 'en',
  origin: SourceOrigin.suwayomi,
);

Map<String, Object?> _data(Map<String, Object?> data) => {'data': data};

/// A server holding AllManga manga 424 (`LHBPxBgNFD26rwgFC`, chapters `55`
/// and `54.5`) whose title search for "mimi" finds `ZqnzvAw2qzQBnZ6WP`.
FakeKartkaHttp _server() => FakeKartkaHttp((request) {
  final body = jsonDecode(request.body!) as Map<String, Object?>;
  final vars = body['variables']! as Map<String, Object?>;
  final data = switch (body['operationName']) {
    'KartkaMangaId' => {
      'mangas': {
        'nodes': [
          if (vars['url'] == 'LHBPxBgNFD26rwgFC') {'id': 424},
        ],
      },
    },
    'KartkaSourceManga' => {
      'fetchSourceManga': {
        'hasNextPage': false,
        'mangas': [
          if (vars['query'] == 'mimi')
            {'id': 777, 'url': 'ZqnzvAw2qzQBnZ6WP', 'title': 'Mimi'},
        ],
      },
    },
    'KartkaChapters' => {
      'fetchMangaAndChapters': {
        'chapters': [
          for (final (i, n) in ['54.5', '55'].indexed)
            {
              'id': 9000 + i,
              'url': n,
              'name': 'Chapter $n',
              'chapterNumber': double.parse(n),
              'uploadDate': '0',
              'sourceOrder': i,
            },
        ],
      },
    },
    'KartkaDetails' => {
      'fetchMangaAndChapters': {
        'manga': {'id': 424, 'url': 'LHBPxBgNFD26rwgFC', 'title': 'My Wife'},
      },
    },
    'KartkaPages' => {
      'fetchChapterPages': {
        'pages': ['/api/v1/manga/424/chapter/${vars['id']}/page/0'],
      },
    },
    _ => throw StateError('unexpected ${body['operationName']}'),
  };
  return FakeKartkaHttp.text(jsonEncode(_data(data)));
});

void main() {
  late FakeKartkaHttp http;
  SuwayomiSource source({String serverId = allMangaServerId}) => SuwayomiSource(
    info: SuwayomiSourceInfo(
      serverId: serverId,
      ref: _ref(serverId),
      supportsLatest: true,
    ),
    client: SuwayomiClient(http: http, settings: () => fixtureSettings),
    settings: () => fixtureSettings,
    titleOf: (_) async => 'Some English Title',
  );

  setUp(() => http = _server());

  test('AllManga legacy urls map to the ids the server keeps', () {
    const urls = AllMangaLegacyUrls();
    expect(urls.mangaUrl(_legacyManga), 'LHBPxBgNFD26rwgFC');
    expect(urls.mangaUrl('LHBPxBgNFD26rwgFC'), isNull);
    expect(urls.searchTitle(_legacyManga), 'boku no tsuma wa kanjou ga nai');
    expect(urls.searchTitle('LHBPxBgNFD26rwgFC'), isNull);
    expect(urls.chapterUrl(_legacyManga, '55'), _legacyChapter);
    expect(urls.chapter(_legacyChapter), (_legacyManga, '55'));
    expect(urls.chapter('55'), isNull);
    expect(legacyUrlsFor(allMangaServerId), isA<AllMangaLegacyUrls>());
    expect(legacyUrlsFor('2499283573021220255'), isNull);
  });

  test('a legacy manga resolves, keeping its legacy chapter urls', () async {
    final s = source();
    final chapters = await s.chapters(_legacyManga);
    // Read marks and stored lists hold the legacy chapter urls.
    expect(chapters.map((c) => c.url), [
      _legacyChapter,
      _legacyChapter.replaceFirst('55', '54.5'),
    ]);
    expect((await s.details(_legacyManga)).url, _legacyManga);
    final pages = await s.pages(_legacyChapter);
    expect(pages.single.imageUrl, endsWith('/chapter/9001/page/0'));
  });

  test('a legacy chapter resolves after a restart (empty caches)', () async {
    final pages = await source().pages(_legacyChapter);
    expect(pages.single.imageUrl, endsWith('/chapter/9001/page/0'));
  });

  test('a legacy chapter its manga does not list is not on the server', () {
    expect(
      () => source().pages(_legacyChapter.replaceFirst('55', '56')),
      throwsA(isA<SuwayomiNotOnServerException>()),
    );
  });

  test('an unseen legacy manga is found by its slug title', () async {
    final details = await source().details(_unseen);
    expect(details.url, _unseen);
  });

  test('other sources keep the urls as they are', () async {
    expect(
      () => source(serverId: '1').chapters(_legacyManga),
      throwsA(isA<SuwayomiNotOnServerException>()),
    );
  });
}
