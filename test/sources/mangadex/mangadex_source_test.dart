import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';
import 'package:kartka/sources/mangadex/rate_limiter.dart';

import 'fakes.dart';

const _solo = '32d76d19-8a05-4db0-9fc2-e0b0648fe9d0';
const _seijo = 'e9d69f82-4c53-44ce-a94b-32303d172227';

void main() {
  late FakeKv kv;
  late List<Duration> waits;
  final t0 = DateTime.utc(2026, 10, 24, 12);
  var now = t0;

  MangaDexSource sourceOver(FakeHttp http, {int feedLimit = 3}) {
    final limiter = RateLimiter(
      mangadexRateRules,
      now: () => now,
      delay: (d) async {
        waits.add(d);
        now = now.add(d);
      },
    );
    return MangaDexSource(
      http: http,
      settings: MangadexSettingsStore(kv),
      limiter: limiter,
      now: () => now,
      feedLimit: feedLimit,
    );
  }

  setUp(() {
    kv = FakeKv();
    waits = [];
    now = t0;
  });

  test('ref is the native mangadex source', () {
    final ref = sourceOver(FakeHttp({})).ref;
    expect(ref.id, 'mangadex');
    expect(ref.origin, SourceOrigin.native);
  });

  test('popular maps the recorded list and sends the User-Agent', () async {
    final http = FakeHttp({
      '/manga': [Canned.file('popular.json')],
    });
    final page = await sourceOver(http).popular(1);
    expect(page.items, hasLength(3));
    expect(page.items.first.title, 'Solo Leveling');
    expect(page.items.first.url, '/manga/$_solo');
    expect(page.items.first.coverUrl, endsWith('.jpg.512.jpg'));
    expect(page.hasNext, isTrue);
    expect(http.sentHeaders.single['User-Agent'], kartkaUserAgent);
  });

  test('latest and search hit /manga with their orders', () async {
    final http = FakeHttp({
      '/manga': [Canned.file('latest.json'), Canned.file('search.json')],
    });
    final s = sourceOver(http);
    expect((await s.latest(1)).items.first.title, 'The Ghostly Doctor');
    final found = await s.search('yotsuba', 1);
    expect(found.items.first.title, startsWith('Yotsuba&!'));
    expect(http.requests[1].queryParameters['title'], 'yotsuba');
  });

  test('pages past the 10000 window are empty without a request', () async {
    final http = FakeHttp({});
    final page = await sourceOver(http).popular(501);
    expect(page, SearchPage.empty);
    expect(http.requests, isEmpty);
  });

  test('details maps authors, status and tracker ids', () async {
    final http = FakeHttp({
      '/manga/$_solo': [Canned.file('details.json')],
    });
    final d = await sourceOver(http).details('/manga/$_solo');
    expect(d.title, 'Solo Leveling');
    expect(d.status, MangaStatus.completed);
    expect(d.authors, contains('Chugong (추공)'));
    expect(d.authors, contains('Jang Sung-Rak (장성락)'));
    expect(d.trackerIds, {
      'anilist': '105398',
      'mal': '121496',
      'mangaupdates': '6z1uqw7',
    });
    expect(d.genres, contains('Action'));
    expect(d.description, startsWith('10 years ago'));
  });

  test('chapters page through the feed by the returned count', () async {
    const path = '/manga/$_seijo/feed';
    final http = FakeHttp({
      '$path?offset=0': [Canned.file('feed_0.json')],
      '$path?offset=3': [Canned.file('feed_3.json')],
    });
    final list = await sourceOver(http).chapters('/manga/$_seijo');
    expect(list, hasLength(4));
    expect(list.first.name, 'Ch. 3 - The Ice Prince Is Dead!');
    expect(list.first.url, '/chapter/7676f896-0a8d-4c5b-a462-073967dd6fb6');
    expect(list.last.scanlator, 'KukoriScans');
    expect(http.requests, hasLength(2));
  });

  test('an empty feed page stops the loop', () async {
    final http = FakeHttp({
      '/manga/x/feed': [const Canned.body('{"data":[],"total":9}')],
    });
    expect(await sourceOver(http).chapters('/manga/x'), isEmpty);
  });

  test('pages use full quality, or data-saver when enabled', () async {
    final routes = {
      '/at-home/server/c1': [Canned.file('at_home.json')],
    };
    final full = await sourceOver(FakeHttp(routes)).pages('/chapter/c1');
    expect(full, hasLength(55));
    expect(full.first.index, 0);
    expect(full.first.imageUrl, contains('/data/2a695934'));
    expect(full.first.headers['User-Agent'], kartkaUserAgent);

    final store = MangadexSettingsStore(kv);
    await store.save(MangadexSettings.defaults.copyWith(dataSaver: true));
    final saver = await sourceOver(FakeHttp(routes)).pages('/chapter/c1');
    expect(saver.first.imageUrl, contains('/data-saver/2a695934'));
  });

  test('data-saver falls back to full quality when the set is empty', () {
    final store = MangadexSettingsStore(kv);
    const body =
        '{"baseUrl":"https://n","chapter":'
        '{"hash":"h","data":["a.jpg"],"dataSaver":[]}}';
    return store.save(MangadexSettings.defaults.copyWith(dataSaver: true)).then(
      (_) async {
        final http = FakeHttp({
          '/at-home/server/c': [const Canned.body(body)],
        });
        final pages = await sourceOver(http).pages('/chapter/c');
        expect(pages.single.imageUrl, 'https://n/data/h/a.jpg');
      },
    );
  });

  test('404 throws MangadexApiException with the API detail', () async {
    final http = FakeHttp({
      '/manga/nope': [Canned.file('error_404.json', status: 404)],
    });
    final call = sourceOver(http).details('/manga/nope');
    await expectLater(
      call,
      throwsA(
        isA<MangadexApiException>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.message, 'message', contains('not found'))
            .having((e) => '$e', 'toString', contains('404')),
      ),
    );
  });

  test('non-JSON error bodies still throw', () async {
    final http = FakeHttp({
      '/manga/x': [const Canned.body('<html>', status: 503)],
    });
    await expectLater(
      sourceOver(http).details('/manga/x'),
      throwsA(isA<MangadexApiException>()),
    );
    final arr = FakeHttp({
      '/manga/y': [const Canned.body('[]', status: 500)],
    });
    await expectLater(
      sourceOver(arr).details('/manga/y'),
      throwsA(isA<KartkaHttpException>()),
    );
  });

  test('429 backs off until Retry-After, then retries', () async {
    final retry = t0.add(const Duration(seconds: 30));
    final http = FakeHttp({
      '/manga/$_solo': [
        Canned.file(
          'rate_limited_429.json',
          status: 429,
          headers: {
            'x-ratelimit-retry-after':
                '${retry.millisecondsSinceEpoch ~/ 1000}',
          },
        ),
        Canned.file('details.json'),
      ],
    });
    final d = await sourceOver(http).details('/manga/$_solo');
    expect(d.title, 'Solo Leveling');
    expect(waits, [const Duration(seconds: 30)]);
  });

  test('429 without a header waits a second; gives up after retries', () {
    final http = FakeHttp({
      '/manga/x': [Canned.file('rate_limited_429.json', status: 429)],
    });
    return expectLater(
      sourceOver(http).details('/manga/x'),
      throwsA(isA<MangadexApiException>()),
    ).then((_) {
      expect(http.requests, hasLength(3));
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 1)]);
    });
  });

  test('default limiter and clock construct', () {
    final s = MangaDexSource(
      http: FakeHttp({}),
      settings: MangadexSettingsStore(kv),
    );
    expect(s.feedLimit, 500);
  });
}
