import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

import 'mu_fakes.dart';

/// A list entry body with [chapter] read on list [listId].
String _entry(int chapter, {int listId = 0}) => jsonEncode({
  'series': {'id': 7},
  'list_id': listId,
  'status': {'chapter': chapter},
});

void main() {
  late KartkaResponse Function(FakeRequest r) handler;
  late FakeKartkaHttp http;
  late MuSessionStore store;
  late MangaUpdatesTracker tracker;
  MuCredentials? answer;

  MangaUpdatesTracker build({MuCredentialsPrompt? prompt}) {
    http = FakeKartkaHttp((r) => handler(r));
    final s = buildStack(http, FakeClock());
    store = s.store;
    return MangaUpdatesTracker(api: s.api, store: s.store, prompt: prompt);
  }

  /// Answers GETs with [entry] (404 when null) and writes with success.
  void remote(String? entry) => handler = (r) => switch (r.method) {
    'GET' when entry == null => fx('list_not_found.json', status: 404),
    'GET' => FakeKartkaHttp.text(entry!),
    _ => fx('list_update_ok.json'),
  };

  List<FakeRequest> writes() =>
      http.requests.where((r) => r.method == 'POST').toList();

  setUp(() {
    handler = (_) => fx('login_ok.json');
    answer = (username: 'kuhy', password: 'pw');
    tracker = build(prompt: () async => answer);
  });

  test('identity', () {
    expect(tracker.id, 'mangaupdates');
    expect(tracker.name, 'MangaUpdates');
  });

  test('login asks for credentials; logout forgets them', () async {
    expect(await tracker.isLoggedIn(), isFalse);
    await tracker.login();
    expect(await tracker.isLoggedIn(), isTrue);
    expect(await tracker.username(), 'kuhy');
    handler = (_) => fx('logout_ok.json');
    await tracker.logout();
    expect(await tracker.isLoggedIn(), isFalse);
    expect(await tracker.username(), isNull);
  });

  test('login cancelled at the prompt: no request', () async {
    answer = null;
    await tracker.login();
    expect(http.requests, isEmpty);
    expect(await tracker.isLoggedIn(), isFalse);
  });

  test('login without a prompt explains itself', () async {
    tracker = build();
    await expectLater(tracker.login(), throwsA(isA<MuAuthException>()));
    await tracker.loginWith('kuhy', 'pw');
    expect(await tracker.isLoggedIn(), isTrue);
  });

  test('search maps to TrackSearchResult with unknown totals', () async {
    handler = (_) => fx('search_berserk.json');
    final hits = await tracker.search('Berserk');
    expect(hits.first.remoteId, '51239621230');
    expect(hits.first.title, 'Berserk');
    expect(hits.first.chapters, isNull);
    expect(hits.first.coverUrl, startsWith('https://'));
  });

  group('fetch', () {
    setUp(() => store.write(testSession));

    test('maps the list entry', () async {
      handler = (_) => fx('list_item_reading.json');
      expect(
        await tracker.fetch('51239621230'),
        const TrackStatus(
          remoteId: '51239621230',
          chaptersRead: 364,
          status: 'read',
        ),
      );
    });

    test('custom list without list_type keeps its id', () async {
      handler = (_) => fx('list_item_custom.json');
      expect((await tracker.fetch('57847596550'))!.status, 'list101');
    });

    test('not listed is null', () async {
      remote(null);
      expect(await tracker.fetch('7'), isNull);
    });

    test('bad remote id throws ArgumentError', () async {
      await expectLater(tracker.fetch('njeqwry'), throwsArgumentError);
    });
  });

  group('pushProgress', () {
    setUp(() => store.write(testSession));

    test('not listed: adds to the reading list with the count', () async {
      remote(null);
      await tracker.pushProgress('7', 12);
      expect(writes().single.url.path, '/v1/lists/series');
      expect(jsonBody(writes().single), [
        {
          'series': {'id': 7},
          'list_id': muReadingList,
          'status': {'chapter': 12},
        },
      ]);
    });

    test('not listed and nothing read: no write', () async {
      remote(null);
      await tracker.pushProgress('7', 0);
      expect(writes(), isEmpty);
    });

    test('listed below local: updates, keeping the list', () async {
      remote(_entry(3, listId: 4));
      await tracker.pushProgress('7', 5);
      expect(writes().single.url.path, '/v1/lists/series/update');
      final body = jsonBody(writes().single)! as List<Object?>;
      expect(body.single, containsPair('list_id', 4));
      expect(body.single, containsPair('status', {'chapter': 5}));
    });

    test('fetches before writing', () async {
      remote(_entry(3));
      await tracker.pushProgress('7', 5);
      expect(http.requests.map((r) => r.method), ['GET', 'POST']);
    });

    glados.Glados2(
      glados.any.intInRange(0, 3000),
      glados.any.intInRange(0, 3000),
    ).test('never lowers the remote count', (remoteCount, local) async {
      http.requests.clear();
      remote(_entry(remoteCount));
      await tracker.pushProgress('7', local);
      if (local <= remoteCount) {
        expect(writes(), isEmpty);
      } else {
        final body = jsonBody(writes().single)! as List<Object?>;
        final status = (body.single! as Map<String, Object?>)['status'];
        expect(status, {'chapter': local});
      }
    });
  });
}
