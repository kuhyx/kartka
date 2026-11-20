import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';

import 'fakes.dart';

const _mangafire = '6084907896154116083';

const _info = SuwayomiSourceInfo(
  serverId: _mangafire,
  ref: SourceRef(
    id: 'suwayomi:$_mangafire',
    name: 'MangaFire',
    lang: 'en',
    origin: SourceOrigin.suwayomi,
  ),
  supportsLatest: true,
);

Object? _filtersResponse() => (jsonDecode(
  File('test/fixtures/suwayomi/filters_mangafire.json').readAsStringSync(),
) as Map<String, Object?>)['response'];

void main() {
  late FakeKartkaHttp http;
  var filtersFail = 0;
  var noFilters = false;

  setUp(() {
    filtersFail = 0;
    noFilters = false;
    http = FakeKartkaHttp((request) {
      final op = (jsonDecode(request.body!) as Map)['operationName'];
      if (op == 'KartkaSourceFilters') {
        if (filtersFail > 0) {
          filtersFail--;
          return FakeKartkaHttp.text('down', status: 503);
        }
        if (noFilters) {
          return FakeKartkaHttp.text('{"data":{"source":{"filters":[]}}}');
        }
        return FakeKartkaHttp.text(jsonEncode(_filtersResponse()));
      }
      return FakeKartkaHttp.text(jsonEncode(fixture('popular')['response']));
    });
  });

  SuwayomiSource source() => SuwayomiSource(
    info: _info,
    client: SuwayomiClient(http: http, settings: () => fixtureSettings),
    settings: () => fixtureSettings,
  );

  test('popular with manga is a SEARCH with type and sort', () async {
    final r = await source().listTyped(Listing.popular, ContentType.manga, 2);
    expect(r.applied, isTrue);
    expect(r.page.items, isNotEmpty);
    final sent = bodies(http);
    expect(sent.map((b) => b['operationName']), [
      'KartkaSourceFilters',
      'KartkaSourceMangaFiltered',
    ]);
    expect(sent.first['variables'], {'id': _mangafire});
    expect(sent.last['query'], SuwayomiQueries.sourceMangaFiltered);
    final vars = sent.last['variables']! as Map<String, Object?>;
    expect(vars['type'], 'SEARCH');
    expect(vars['query'], '');
    expect(vars['page'], 2);
    expect(vars['filters'], [
      for (final (i, on) in [true, false, false, false].indexed)
        {
          'position': 2,
          'groupChange': {'position': i, 'checkBoxState': on},
        },
      {'position': 16, 'selectState': 8},
    ]);
  });

  test('search keeps the query; the filter list is read once', () async {
    final s = source();
    await s.listTyped(Listing.search, ContentType.mangaManhwa, 1, query: 'x');
    await s.listTyped(Listing.latest, ContentType.manga, 1);
    final sent = bodies(http);
    expect(
      sent.where((b) => b['operationName'] == 'KartkaSourceFilters'),
      hasLength(1),
    );
    final search = sent[1]['variables']! as Map<String, Object?>;
    expect(search['query'], 'x');
    expect((search['filters']! as List).length, 4);
    final latest = sent[2]['variables']! as Map<String, Object?>;
    expect((latest['filters']! as List).last, {
      'position': 16,
      'selectState': 0,
    });
  });

  test('a failed filter read lists unfiltered and is retried', () async {
    filtersFail = 1;
    final s = source();
    final r = await s.listTyped(Listing.popular, ContentType.manga, 1);
    expect(r.applied, isFalse);
    expect(bodies(http).last['query'], SuwayomiQueries.sourceManga);
    expect((bodies(http).last['variables']! as Map)['type'], 'POPULAR');
    final again = await s.listTyped(Listing.popular, ContentType.manga, 1);
    expect(again.applied, isTrue);
  });

  test('no type filter: the plain request, not applied', () async {
    noFilters = true;
    final r = await source().listTyped(Listing.latest, ContentType.manga, 1);
    expect(r.applied, isFalse);
    expect(bodies(http).last['query'], SuwayomiQueries.sourceManga);
    expect(bodies(http).last['variables'], {
      'source': _mangafire,
      'type': 'LATEST',
      'page': 1,
    });
  });
}
