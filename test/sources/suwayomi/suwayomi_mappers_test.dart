import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';

import 'fakes.dart';

Map<String, Object?> _data(String name) =>
    (fixture(name)['response']! as Map<String, Object?>)['data']!
        as Map<String, Object?>;

String _resolve(String p) => 'https://h$p';

void main() {
  test('every fixture was recorded with the client\'s own documents', () {
    const documents = {
      SuwayomiQueries.about, SuwayomiQueries.sources,
      SuwayomiQueries.sourceManga, SuwayomiQueries.mangaId,
      SuwayomiQueries.details, SuwayomiQueries.chapters,
      SuwayomiQueries.chapterId, SuwayomiQueries.pages,
      SuwayomiQueries.extensions, SuwayomiQueries.updateExtension,
    };
    final names = fixtureNames();
    expect(names, hasLength(greaterThanOrEqualTo(19)));
    for (final name in names) {
      final query = (fixture(name)['request']! as Map)['query'];
      expect(documents, contains(query), reason: '$name.json drifted');
    }
  });

  test('sources keep 19-digit ids as strings', () {
    final nodes = (_data('sources')['sources']! as Map)['nodes']! as List;
    final info = SuwayomiSourceInfo.fromJson(
      nodes.last! as Map<String, Object?>,
    );
    expect(info.serverId, mangadexEn);
    expect(info.ref.id, 'suwayomi:2499283573021220255');
    expect(info.ref.origin, SourceOrigin.suwayomi);
    expect(info.supportsLatest, isTrue);
    expect(
      SuwayomiSourceInfo.fromJson(const {'id': '7', 'name': 'n', 'lang': 'x'})
          .supportsLatest,
      isFalse,
    );
  });

  test('details map authors, genres, status and cover', () {
    final manga = (_data('details')['fetchMangaAndChapters']! as Map)['manga']!
        as Map<String, Object?>;
    final d = mangaDetailsFrom(manga, 'suwayomi:1', _resolve);
    expect(d.authors, ['Tsutsumi Kotatsu']);
    expect(d.genres, contains('Comedy'));
    expect(d.status, isNot(MangaStatus.unknown));
    expect(d.coverUrl, 'https://h/api/v1/manga/1/thumbnail');
  });

  test('details tolerate missing optional fields', () {
    final d = mangaDetailsFrom(
      const {
        'url': '/m',
        'title': 't',
        'author': 'A, B',
        'artist': 'B',
        'description': ' ',
        'status': 'ON_HIATUS',
        'thumbnailUrl': '',
      },
      's',
      _resolve,
    );
    expect(d.authors, ['A', 'B']);
    expect(d.description, isNull);
    expect(d.genres, isEmpty);
    expect(d.status, MangaStatus.onHiatus);
    expect(d.coverUrl, isNull);
    expect(
      mangaDetailsFrom(const {'url': '/m', 'title': 't', 'status': '?'}, 's',
              _resolve)
          .status,
      MangaStatus.unknown,
    );
  });

  test('every server status has a kartka status', () {
    for (final (wire, status) in [
      ('UNKNOWN', MangaStatus.unknown),
      ('ONGOING', MangaStatus.ongoing),
      ('COMPLETED', MangaStatus.completed),
      ('LICENSED', MangaStatus.licensed),
      ('PUBLISHING_FINISHED', MangaStatus.publishingFinished),
      ('CANCELLED', MangaStatus.cancelled),
    ]) {
      final m = {'url': '/m', 'title': 't', 'status': wire};
      expect(mangaDetailsFrom(m, 's', _resolve).status, status);
    }
  });

  test('chapters treat -1 numbers and 0 dates as unknown', () {
    final c = chapterFrom(const {
      'url': '/c',
      'name': 'Oneshot',
      'chapterNumber': -1.0,
      'uploadDate': '0',
      'scanlator': '',
    });
    expect(c.number, isNull);
    expect(c.uploadedAt, isNull);
    expect(c.scanlator, isNull);
    final dated = chapterFrom(const {
      'url': '/c',
      'name': 'n',
      'chapterNumber': 2,
      'uploadDate': '1790429088000',
    });
    expect(dated.number, 2.0);
    expect(dated.uploadedAt, DateTime.utc(2026, 9, 26, 13, 24, 48));
  });

  test('pages are indexed in order with the given headers', () {
    final refs = pageRefsFrom(const ['/p0', 'https://cdn/p1'], (p) => p.startsWith('/') ? _resolve(p) : p, {
      'a': 'b',
    });
    expect(refs.map((r) => r.imageUrl), ['https://h/p0', 'https://cdn/p1']);
    expect(refs.map((r) => r.index), [0, 1]);
    expect(refs.last.headers, {'a': 'b'});
  });
}
