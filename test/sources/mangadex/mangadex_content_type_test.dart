import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';
import 'package:kartka/sources/mangadex/mangadex_urls.dart';

import 'fakes.dart';

const _manga = ContentTypes({ContentType.manga});
const _mangaManhwa = ContentTypes({ContentType.manga, ContentType.manhwa});

void main() {
  const urls = MangadexUrls(MangadexSettings.defaults);

  test('languages per ticked set: manga excludes the unticked rest', () {
    MangadexOrigin of(ContentTypes t) => MangadexUrls.originOf(t);
    expect(of(_manga).excluded, ['ko', 'zh', 'zh-hk']);
    expect(of(_manga).only, isEmpty);
    expect(of(_mangaManhwa).excluded, ['zh', 'zh-hk']);
    // Without manga, only the ticked languages: unknown counts as manga.
    final noManga = ContentTypes.all.toggled(ContentType.manga);
    expect(of(noManga).only, ['ko', 'zh', 'zh-hk']);
    expect(of(noManga).excluded, isEmpty);
    expect(of(ContentTypes.all).only, isEmpty);
    expect(of(ContentTypes.all).excluded, isEmpty);
  });

  test('listings carry originalLanguage[] only when narrowed', () {
    expect(
      urls.popular(1, origin: (only: ['ja'], excluded: [])).queryParametersAll,
      containsPair('originalLanguage[]', ['ja']),
    );
    expect(
      urls
          .search('x', 1, origin: (only: [], excluded: ['ko']))
          .queryParametersAll,
      containsPair('excludedOriginalLanguage[]', ['ko']),
    );
    // No list: the URL is exactly today's.
    expect(
      urls.latest(1, origin: (only: ['ja'], excluded: [])),
      isNot(urls.latest(1)),
    );
    expect(
      urls.latest(1).queryParametersAll.keys,
      isNot(contains('originalLanguage[]')),
    );
  });

  test('the source narrows every listing and always applies it', () async {
    final http = fixtureHttp({
      '/manga': [Canned.file('popular.json')],
    });
    final source = MangaDexSource(
      http: http,
      settings: MangadexSettingsStore(MemoryKeyValueStore()),
    );
    for (final l in Listing.values) {
      final r = await source.listTyped(l, _mangaManhwa, 1, query: 'q');
      expect(r.applied, isTrue);
      expect(r.page.items, isNotEmpty);
    }
    final sent = [for (final r in http.requests) r.url.queryParametersAll];
    expect(
      sent,
      everyElement(containsPair('excludedOriginalLanguage[]', ['zh', 'zh-hk'])),
    );
    expect(sent[0], contains('order[followedCount]'));
    expect(sent[1], contains('order[latestUploadedChapter]'));
    expect(sent[2]['title'], ['q']);
  });
}
