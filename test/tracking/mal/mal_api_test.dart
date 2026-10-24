import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/mal/mal_api.dart';
import 'package:kartka/tracking/mal/mal_models.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

void main() {
  late FakeTransport http;
  late MalApi api;

  setUp(() {
    http = FakeTransport((_) => fx(200, 'search_berserk.json'));
    api = buildApi(http);
  });

  group('search', () {
    test('uses the client-id header and parses hits', () async {
      final hits = await api.search('Berserk');
      final req = http.requests.single;
      expect(req.headers, {'X-MAL-CLIENT-ID': 'cid'});
      expect(req.url.path, '/v2/manga');
      expect(req.url.queryParameters, {
        'q': 'Berserk',
        'limit': '10',
        'fields': 'num_chapters',
        'nsfw': 'true',
      });
      expect(hits.first.id, 2);
      expect(hits.first.title, 'Berserk');
      expect(hits.first.coverUrl, contains('157897.jpg'));
      expect(hits.first.totalChapters, isNull, reason: '0 means unknown');
      expect(hits.last.coverUrl, isNull);
      expect(hits.last.totalChapters, 1);
    });

    test('long titles are cut to 64 characters', () async {
      await api.search('x' * 100);
      expect(http.requests.single.url.queryParameters['q'], 'x' * 64);
    });

    test('blank title returns nothing without a request', () async {
      expect(await api.search('   '), isEmpty);
      expect(http.requests, isEmpty);
    });

    test('empty result', () async {
      http.handler = (_) => fx(200, 'search_empty.json');
      expect(await api.search('zzz'), isEmpty);
    });

    test('HTTP error becomes MalException with the status', () async {
      http.handler = (_) => const MalResponse(403, '');
      await expectLater(
        api.search('Berserk'),
        throwsA(isA<MalException>().having((e) => e.statusCode, 's', 403)),
      );
    });
  });

  group('manga', () {
    test('fetches list status with a bearer token', () async {
      http.handler = (_) => fx(200, 'manga_reading.json');
      final manga = (await api.manga(2))!;
      final req = http.requests.single;
      expect(req.url.path, '/v2/manga/2');
      expect(req.url.queryParameters['fields'], 'num_chapters,my_list_status');
      expect(req.headers['Authorization'], 'Bearer access-0');
      expect(manga.listStatus!.chaptersRead, 380);
      expect(manga.listStatus!.status, 'reading');
      expect(manga.listStatus!.score, isNull, reason: '0 means unscored');
    });

    test('not on the list has no status', () async {
      http.handler = (_) => fx(200, 'manga_not_listed.json');
      expect((await api.manga(44347))!.listStatus, isNull);
    });

    test('scored entry keeps its score', () async {
      http.handler = (_) => fx(200, 'manga_finished.json');
      final manga = (await api.manga(25))!;
      expect(manga.listStatus!.score, 9);
      expect(manga.totalChapters, 116);
    });

    test('404 is null', () async {
      http.handler = (_) => const MalResponse(404, '');
      expect(await api.manga(1), isNull);
    });

    test('malformed body is a MalException', () async {
      http.handler = (_) => const MalResponse(200, '[]');
      await expectLater(api.manga(2), throwsA(isA<MalException>()));
      http.handler = (_) => const MalResponse(200, '{"id":"x"}');
      await expectLater(api.manga(2), throwsA(isA<MalException>()));
    });
  });

  group('updateListStatus', () {
    test('PATCHes form-encoded fields', () async {
      http.handler = (_) => fx(200, 'list_status_updated.json');
      final status = await api.updateListStatus(
        2,
        chaptersRead: 381,
        status: 'reading',
      );
      final req = http.requests.single;
      expect(req.method, MalMethod.patch);
      expect(req.url.path, '/v2/manga/2/my_list_status');
      expect(req.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(Uri.splitQueryString(req.body!), {
        'num_chapters_read': '381',
        'status': 'reading',
      });
      expect(status, const MalListStatus(status: 'reading', chaptersRead: 381));
    });

    test('status is optional', () async {
      http.handler = (_) => fx(200, 'list_status_updated.json');
      await api.updateListStatus(2, chaptersRead: 381);
      expect(Uri.splitQueryString(http.requests.single.body!), {
        'num_chapters_read': '381',
      });
    });

    test('malformed PATCH response is a MalException', () async {
      http.handler = (_) => const MalResponse(200, '{}');
      await expectLater(
        api.updateListStatus(2, chaptersRead: 1),
        throwsA(isA<MalException>()),
      );
    });

    test('error status throws', () async {
      http.handler = (_) => const MalResponse(400, '{"error":"bad"}');
      await expectLater(
        api.updateListStatus(2, chaptersRead: 1),
        throwsA(isA<MalException>()),
      );
    });
  });

  test('models compare by value', () {
    const a = MalListStatus(status: 'reading', chaptersRead: 1, score: 5);
    expect(
      a,
      const MalListStatus(status: 'reading', chaptersRead: 1, score: 5),
    );
    expect(
      a.hashCode,
      isNot(const MalListStatus(status: 'x', chaptersRead: 1).hashCode),
    );
    expect(a.toString(), 'MalListStatus(reading, 1)');
  });
}
