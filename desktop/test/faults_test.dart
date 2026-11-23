import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/faults.dart';
import 'package:test/test.dart';

/// Agent-only fault injection: the states the error-report fixes handle
/// (offline, dropped connection, our server's 500, the upstream's DNS or
/// WebView failing), on demand, without touching the real network.
void main() {
  late Directory dir;
  late File file;
  late ProxyFaults faults;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('kartka_faults');
    file = File('${dir.path}/faults.json');
    faults = ProxyFaults(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProxyFault? at(String url, [String body = '']) =>
      faults.match(Uri.parse(url), utf8.encode(body));

  test('no file, an empty or a broken one: nothing injected', () {
    expect(at('https://a.org/x'), isNull);
    file.writeAsStringSync('{');
    expect(at('https://a.org/x'), isNull);
  });

  test('offline is a failed host lookup for that host only', () {
    file.writeAsStringSync('{"a.org": "offline"}');
    expect(
      at('https://a.org/x')!.error,
      contains("Failed host lookup: 'a.org'"),
    );
    expect(at('https://b.org/x'), isNull);
    file.writeAsStringSync('{"*": "offline"}');
    expect(at('https://b.org/x')!.error, contains('Failed host lookup'));
  });

  test('abort-once drops one request, then lets them through', () {
    file.writeAsStringSync('{"a.org": "abort-once"}');
    expect(at('https://a.org/x')!.error, contains('connection abort'));
    expect(at('https://a.org/x'), isNull);
    file.writeAsStringSync('{"a.org":"abort-once"}');
    expect(at('https://a.org/x'), isNotNull, reason: 'a new file re-arms');
  });

  test('page-500 answers 500 for page images only', () {
    file.writeAsStringSync('{"s.org": "page-500"}');
    expect(at('https://s.org/api/v1/manga/1/chapter/2/page/0')!.status, 500);
    expect(at('https://s.org/api/graphql'), isNull);
  });

  test('webview and upstream-dns answer the matching GraphQL call', () {
    file.writeAsStringSync('{"s.org": "webview"}');
    final pages = at(
      'https://s.org/api/graphql',
      '{"operationName":"KartkaPages"}',
    );
    expect(pages!.status, 200);
    expect(pages.body, contains('Timed out waiting for WebView after 20s'));
    expect(
      at('https://s.org/api/graphql', '{"operationName":"KartkaAbout"}'),
      isNull,
    );
    file.writeAsStringSync('{"s.org": "upstream-dns"}');
    final details = at(
      'https://s.org/api/graphql',
      '{"operationName":"KartkaDetails"}',
    );
    expect(details!.body, contains('Name or service not known'));
    expect(jsonDecode(details.body!), contains('errors'));
  });

  test('gone: the server has no such manga (lookup and search empty)', () {
    file.writeAsStringSync('{"s.org": "gone"}');
    const api = 'https://s.org/api/graphql';
    final lookup = at(api, '{"operationName":"KartkaMangaId"}');
    expect(jsonDecode(lookup!.body!), {
      'data': {
        'mangas': {'nodes': <Object>[]},
      },
    });
    final search = at(api, '{"operationName":"KartkaSourceManga"}');
    expect(jsonDecode(search!.body!), {
      'data': {
        'fetchSourceManga': {'hasNextPage': false, 'mangas': <Object>[]},
      },
    });
    expect(at(api, '{"operationName":"KartkaDetails"}'), isNull);
  });

  test('slow-pages delays the page list, then lets it through', () {
    file.writeAsStringSync('{"s.org": "slow-pages"}');
    final pages = at(
      'https://s.org/api/graphql',
      '{"operationName":"KartkaPages"}',
    )!;
    expect(pages.delay, ProxyFaults.slowPages);
    expect(pages.status, isNull, reason: 'forwarded after the delay');
    expect(at('https://s.org/api/graphql', '{"operationName":"X"}'), isNull);
    file.writeAsStringSync('{"s.org": "slow-pages:250"}');
    expect(
      at('https://s.org/api/graphql', '{"operationName":"KartkaPages"}')!.delay,
      const Duration(milliseconds: 250),
    );
  });

  test('slow-details delays details and the chapter list only', () {
    file.writeAsStringSync('{"s.org": "slow-details:1500"}');
    for (final op in ['KartkaDetails', 'KartkaChapters']) {
      expect(
        at('https://s.org/api/graphql', '{"operationName":"$op"}')!.delay,
        const Duration(milliseconds: 1500),
      );
    }
    expect(
      at('https://s.org/api/graphql', '{"operationName":"KartkaPages"}'),
      isNull,
    );
  });

  test('slow-* hold MangaDex REST calls by path (f6)', () {
    const api = 'https://api.mangadex.org';
    file.writeAsStringSync('{"api.mangadex.org": "slow-details:900"}');
    expect(
      at('$api/manga/abc/feed?limit=500')!.delay,
      const Duration(milliseconds: 900),
    );
    expect(at('$api/manga/abc?includes[]=author'), isNotNull);
    expect(at('$api/at-home/server/c1'), isNull);
    expect(at('$api/manga?title=x'), isNull, reason: 'a search');
    file.writeAsStringSync('{"api.mangadex.org": "slow-pages:900"}');
    expect(
      at('$api/at-home/server/c1')!.delay,
      const Duration(milliseconds: 900),
    );
    expect(at('$api/manga/abc/feed'), isNull);
  });

  test('slow-images holds page images only (f7)', () {
    file.writeAsStringSync('{"*": "slow-images:700"}');
    for (final url in [
      'https://cdn.x.org/data/ab/1-x.png',
      'https://cdn.x.org/data/ab/2.JPG',
      'https://cdn.x.org/a/3.webp?token=1',
      'http://127.0.0.1:4567/api/v1/manga/5/chapter/2/page/0',
    ]) {
      expect(at(url)?.delay, const Duration(milliseconds: 700), reason: url);
    }
    expect(at('https://api.mangadex.org/at-home/server/x'), isNull);
    expect(
      at('https://s.org/api/graphql', '{"operationName":"KartkaPages"}'),
      isNull,
    );
    file.writeAsStringSync('{"*": "slow-images"}');
    expect(at('https://cdn.x.org/1.jpeg')?.delay, ProxyFaults.slowPages);
  });

  test('hide-newest drops the newest chapter from the first feed page', () {
    file.writeAsStringSync('{"api.mangadex.org": "hide-newest"}');
    const feed = 'https://api.mangadex.org/manga/m1/feed';
    final fault = at('$feed?offset=0&order[chapter]=desc')!;
    expect(fault.delay, isNull);
    expect(fault.status, isNull, reason: 'forwarded, then rewritten');
    String chapter(String v, String n) =>
        '{"id":"$v-$n","attributes":{"volume":"$v","chapter":"$n"}}';
    final body =
        '{"result":"ok","data":[${chapter('9', '80')},${chapter('9', '80')},'
        '${chapter('9', '79')}],"limit":500,"offset":0,"total":3}';
    final out = jsonDecode(fault.rewrite!(body)) as Map<String, Object?>;
    expect([for (final c in out['data']! as List) (c as Map)['id']], ['9-79']);
    expect(out['total'], 1);
    expect(fault.rewrite!('not json'), 'not json');
    expect(at('$feed?offset=500'), isNull, reason: 'older pages untouched');
    expect(at('https://api.mangadex.org/manga/m1'), isNull);
  });
}
