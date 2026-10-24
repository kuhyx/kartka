import 'package:flutter_test/flutter_test.dart';

import 'package:kartka/plugins/runtime/engine.dart';

import 'replay.dart';

/// The three real Mangayomi extensions, replayed offline from recordings,
/// on [engine] (`extensions_test.dart` runs them on QuickJS).
void extensionCases(JsEngineFactory engine) {
  const slow = Timeout(Duration(seconds: 50));
  Map<String, Object?> first(Map<String, Object?> page) =>
      ((page['items']! as List).first! as Map).cast<String, Object?>();

  test('weebcentral: all six entry points (HTML source)', () async {
    final r = await replay('weebcentral', engine: engine);
    expect((r.popular['items']! as List).length, 32);
    expect(r.popular['hasNext'], true);
    expect(first(r.popular)['title'], 'Junjou Romantica');
    expect(first(r.latest)['title'], 'Code: Breaker');
    expect(first(r.search)['title'], 'Solo Leveling');
    expect(r.search['hasNext'], false);
    expect(r.details['title'], 'Solo Leveling');
    expect(r.details['authors'], ['GEE So-Lyung']);
    expect(r.details['genres'], ['Action', 'Adventure', 'Fantasy', 'Shounen']);
    expect(r.details['status'], 'completed');
    expect(r.chapters.length, 201);
    expect(r.chapters.first, {
      'url': '01J76XZ666GREP4DQDKEP1YDZG',
      'name': 'Chapter 200',
      'number': 200,
      'uploadedAt': '2024-09-07T17:04:15.717Z',
      'scanlator': null,
    });
    expect(r.pages.length, 12);
    expect(
      (r.pages.first! as Map)['headers'],
      containsPair('Referer', 'https://weebcentral.com/'),
    );
  }, timeout: slow);

  test('webtoons: listings, details, pages; no chapters (upstream)', () async {
    final r = await replay(
      'webtoons',
      engine: engine,
      pagesUrl:
          'https://www.webtoons.com/en/action/a-wimps-tower-strategy-guide/'
          'episode-1/viewer?title_no=9701&episode_no=1',
    );
    expect((r.popular['items']! as List).length, 162);
    expect(first(r.popular)['title'], 'Star Catcher');
    expect(first(r.latest)['title'], 'The Academy is Doomed');
    expect(first(r.search)['title'], 'A Wimp’s Tower Strategy Guide');
    expect(r.details['title'], 'The White Tower’s Rogue Mage');
    expect(r.details['status'], 'ongoing');
    // The extension returns no cover in getDetail; the listing's cover is used.
    expect(
      r.details['coverUrl'],
      startsWith('https://webtoon-phinf.pstatic.net/'),
    );
    // m.webtoons.com no longer serves ul#_episodeList: the extension finds
    // no episodes (it would in Mangayomi too). Not a shim gap.
    expect(r.chapters, isEmpty);
    expect(r.pages.length, 223);
  }, timeout: slow);

  test('mangadex: all six entry points (JSON API source, prefs)', () async {
    final r = await replay('mangadex', engine: engine);
    expect(
      first(r.popular)['url'],
      '/manga/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0',
    );
    expect(first(r.popular)['title'], 'Solo Leveling');
    expect(first(r.latest)['title'], '81diver');
    expect(
      first(r.search)['url'],
      '/manga/b00acc54-2bf1-440e-8f33-da87227d82d6',
    );
    expect(r.details['authors'], ['Digishoku']);
    expect(r.chapters.length, 3);
    expect((r.chapters.last! as Map)['number'], 1);
    expect((r.chapters.last! as Map)['scanlator'], 'Lyra Scans');
    expect(r.pages.length, 93);
    expect(
      (r.pages.first! as Map)['imageUrl'],
      contains('.mangadex.network/data/'),
    );
  }, timeout: slow);
}
