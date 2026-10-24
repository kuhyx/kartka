import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/mangaupdates/mu_api.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

import 'mu_fakes.dart';

void main() {
  late KartkaResponse Function(FakeRequest r) handler;
  late FakeKartkaHttp http;
  late MuApi api;
  late MuSessionStore store;

  setUp(() {
    handler = (_) => fx('login_ok.json');
    http = FakeKartkaHttp((r) => handler(r));
    final s = buildStack(http, FakeClock());
    api = s.api;
    store = s.store;
  });

  group('login', () {
    test('PUTs credentials and stores the session token', () async {
      final session = await api.login('kuhy', 'pw');
      expect(session.token, 'mu-session-abc123');
      expect(session.username, 'kuhy');
      expect((await store.read())?.token, 'mu-session-abc123');
      final r = http.requests.single;
      expect(r.method, 'PUT');
      expect(r.url.path, '/v1/account/login');
      expect(jsonBody(r), {'username': 'kuhy', 'password': 'pw'});
    });

    test('401 throws the server reason and stores nothing', () async {
      handler = (_) => fx('login_bad.json', status: 401);
      await expectLater(
        api.login('kuhy', 'bad'),
        throwsA(
          isA<MuAuthException>()
              .having((e) => e.message, 'message', contains('Invalid'))
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(await store.read(), isNull);
    });

    test('200 without a token is an auth failure', () async {
      handler = (_) => fx('logout_ok.json');
      await expectLater(api.login('a', 'b'), throwsA(isA<MuAuthException>()));
    });

    test('non-JSON error body still fails cleanly', () async {
      handler = (_) => FakeKartkaHttp.text('<html>', status: 500);
      await expectLater(
        api.login('a', 'b'),
        throwsA(isA<MuAuthException>().having((e) => e.statusCode, 's', 500)),
      );
    });
  });

  group('logout', () {
    test('POSTs logout with the token and forgets it', () async {
      await store.write(testSession);
      handler = (_) => fx('logout_ok.json');
      await api.logout();
      final r = http.requests.single;
      expect(r.url.path, '/v1/account/logout');
      expect(r.headers['Authorization'], 'Bearer tok');
      expect(await store.read(), isNull);
    });

    test('forgets the token even when the server call fails', () async {
      await store.write(testSession);
      handler = (_) => throw KartkaHttpException(Uri.parse('https://x'), 0);
      await api.logout();
      expect(await store.read(), isNull);
    });

    test('logged out already: no request', () async {
      await api.logout();
      expect(http.requests, isEmpty);
    });
  });

  group('search', () {
    test('POSTs the title and maps hits, skipping novels', () async {
      handler = (_) => fx('search_berserk.json');
      final hits = await api.search('  Berserk ');
      expect(jsonBody(http.requests.single), {
        'search': 'Berserk',
        'perpage': 10,
      });
      expect(hits.map((h) => h.id), [51239621230, 15180124327]);
      expect(hits.first.title, 'Berserk');
      expect(hits.first.coverUrl, endsWith('thumb/i501230.png'));
      expect(hits.last.coverUrl, endsWith('/i1.jpg'));
    });

    test('blank title: no request', () async {
      expect(await api.search('  '), isEmpty);
      expect(http.requests, isEmpty);
    });

    test('malformed body throws MuException', () async {
      handler = (_) => FakeKartkaHttp.text('{"results": 3}');
      await expectLater(api.search('x'), throwsA(isA<MuException>()));
      handler = (_) => FakeKartkaHttp.text('[]');
      await expectLater(api.search('x'), throwsA(isA<MuException>()));
      handler = (_) => FakeKartkaHttp.text('{"results": [{"record": {}}]}');
      await expectLater(api.search('x'), throwsA(isA<MuException>()));
    });

    test('server error throws with status', () async {
      handler = (_) => FakeKartkaHttp.text('{}', status: 500);
      await expectLater(
        api.search('x'),
        throwsA(isA<MuException>().having((e) => e.statusCode, 's', 500)),
      );
    });
  });

  group('list entries', () {
    setUp(() => store.write(testSession));

    test('listItem parses the entry', () async {
      handler = (_) => fx('list_item_reading.json');
      final item = (await api.listItem(51239621230))!;
      expect(http.requests.single.url.path, '/v1/lists/series/51239621230');
      expect(http.requests.single.headers['Authorization'], 'Bearer tok');
      expect(item.listId, 0);
      expect(item.chapter, 364);
      expect(item.status, 'read');
    });

    test('listItem is null on 404', () async {
      handler = (_) => fx('list_not_found.json', status: 404);
      expect(await api.listItem(1), isNull);
    });

    // Live API, 2026-10-24: with a dead or missing token the list endpoints
    // answer 200 `{}` (and writes 200 "success") instead of 401.
    test('200 {} with a dead session: forgets it and throws', () async {
      handler = (r) => r.url.path.endsWith('/account/profile')
          ? fx('profile_required.json', status: 401)
          : fx('list_item_anonymous.json');
      await expectLater(api.listItem(1), throwsA(isA<MuAuthException>()));
      expect(http.requests.last.headers['Authorization'], 'Bearer tok');
      expect(await store.read(), isNull);
    });

    test('200 {} with a live session: not listed', () async {
      handler = (r) => r.url.path.endsWith('/account/profile')
          ? fx('profile_ok.json')
          : fx('list_item_anonymous.json');
      expect(await api.listItem(1), isNull);
      expect(await store.read(), isNotNull);
    });

    test('200 {} and the session check fails: throws', () async {
      handler = (r) => r.url.path.endsWith('/account/profile')
          ? FakeKartkaHttp.text('', status: 503)
          : fx('list_item_anonymous.json');
      await expectLater(
        api.listItem(1),
        throwsA(isA<MuException>().having((e) => e.statusCode, 's', 503)),
      );
    });

    test('401 forgets the session and throws', () async {
      handler = (_) => fx('not_logged_in.json', status: 401);
      await expectLater(api.listItem(1), throwsA(isA<MuAuthException>()));
      expect(await store.read(), isNull);
    });

    test('not logged in: throws without a request', () async {
      await store.clear();
      await expectLater(api.listItem(1), throwsA(isA<MuAuthException>()));
      expect(http.requests, isEmpty);
    });

    test('addToList POSTs series, list and chapter', () async {
      handler = (_) => fx('list_add_ok.json');
      await api.addToList(7, chapter: 3);
      final r = http.requests.single;
      expect(r.url.path, '/v1/lists/series');
      expect(jsonBody(r), [
        {
          'series': {'id': 7},
          'list_id': 0,
          'status': {'chapter': 3},
        },
      ]);
    });

    test('updateChapter keeps the given list', () async {
      handler = (_) => fx('list_update_ok.json');
      await api.updateChapter(7, listId: 4, chapter: 9);
      final r = http.requests.single;
      expect(r.url.path, '/v1/lists/series/update');
      expect(jsonBody(r), [
        {
          'series': {'id': 7},
          'list_id': 4,
          'status': {'chapter': 9},
        },
      ]);
    });

    test('a failed write throws MuException with status', () async {
      handler = (_) => fx('update_delay.json', status: 400);
      await expectLater(
        api.updateChapter(7, listId: 0, chapter: 1),
        throwsA(isA<MuException>().having((e) => e.statusCode, 's', 400)),
      );
    });
  });
}
