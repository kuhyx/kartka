import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';
import 'package:kartka/sources/mangadex/mangadex_urls.dart';

import 'fakes.dart';

void main() {
  const urls = MangadexUrls(MangadexSettings.defaults);

  test('original languages per content type', () {
    expect(MangadexUrls.originalLanguagesOf(ContentType.manga), ['ja']);
    expect(MangadexUrls.originalLanguagesOf(ContentType.mangaManhwa), [
      'ja',
      'ko',
    ]);
    expect(MangadexUrls.originalLanguagesOf(ContentType.all), isEmpty);
  });

  test('listings carry originalLanguage[] only when narrowed', () {
    expect(
      urls.popular(1, original: const ['ja']).queryParametersAll,
      containsPair('originalLanguage[]', ['ja']),
    );
    expect(
      urls.search('x', 1, original: const ['ja', 'ko']).queryParametersAll,
      containsPair('originalLanguage[]', ['ja', 'ko']),
    );
    // No list: the URL is exactly today's.
    expect(urls.latest(1, original: const ['ja']), isNot(urls.latest(1)));
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
      final r = await source.listTyped(
        l,
        ContentType.mangaManhwa,
        1,
        query: 'q',
      );
      expect(r.applied, isTrue);
      expect(r.page.items, isNotEmpty);
    }
    final sent = [for (final r in http.requests) r.url.queryParametersAll];
    expect(
      sent,
      everyElement(containsPair('originalLanguage[]', ['ja', 'ko'])),
    );
    expect(sent[0], contains('order[followedCount]'));
    expect(sent[1], contains('order[latestUploadedChapter]'));
    expect(sent[2]['title'], ['q']);
  });
}
