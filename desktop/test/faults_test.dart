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
}
