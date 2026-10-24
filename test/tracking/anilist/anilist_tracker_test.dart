import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/anilist/anilist_api.dart';
import 'package:kartka/tracking/anilist/anilist_auth.dart';
import 'package:kartka/tracking/anilist/anilist_parse.dart';
import 'package:kartka/tracking/anilist/anilist_queries.dart';
import 'package:kartka/tracking/anilist/anilist_tracker.dart';
import 'package:kartka/tracking/common/tracker.dart';

import '../fakes.dart';

final Uri _web = Uri.parse('http://127.0.0.1:8791/oauth');

void main() {
  late FakeHttp http;
  late MemoryKv secrets;
  late FakeOAuth oauth;
  late AniListTracker tracker;

  setUp(() {
    http = FakeHttp();
    secrets = MemoryKv();
    oauth = FakeOAuth(
      _web,
      result: _web.replace(fragment: 'access_token=TOK&expires_in=3600'),
    );
    tracker = AniListTracker(
      api: AniListApi(http, limiter: freeLimiter()),
      auth: AniListAuth(
        secrets: secrets,
        oauth: oauth,
        clientIds: const AniListClientIds(android: 'A', web: 'W'),
      ),
    );
  });

  Future<void> logIn() => tracker.login();

  test('identity', () {
    expect(tracker.id, 'anilist');
    expect(tracker.name, 'AniList');
  });

  test('login and logout drive isLoggedIn', () async {
    expect(await tracker.isLoggedIn(), isFalse);
    await logIn();
    expect(await tracker.isLoggedIn(), isTrue);
    await tracker.logout();
    expect(await tracker.isLoggedIn(), isFalse);
  });

  test('search works anonymously and parses hits', () async {
    http.queue.add(reply(fixtureText('search_yotsuba')));
    final hits = await tracker.search('Yotsuba');
    expect(hits.first.remoteId, '30104');
    expect(http.sent.single.json['query'], searchQuery);
    expect(http.sent.single.variables, {'search': 'Yotsuba'});
    expect(http.sent.single.headers.containsKey('Authorization'), isFalse);
  });

  test('search sends the token when logged in', () async {
    await logIn();
    http.queue.add(reply(fixtureText('search_empty')));
    expect(await tracker.search('x'), isEmpty);
    expect(http.sent.single.headers['Authorization'], 'Bearer TOK');
  });

  test('fetch maps the entry and needs a login', () async {
    await expectLater(tracker.fetch('30104'), throwsStateError);
    await logIn();
    http.queue.add(reply(fixtureText('fetch_entry')));
    final s = await tracker.fetch('30104');
    expect(s!.chaptersRead, 42);
    expect(http.sent.single.variables, {'id': 30104});
  });

  test('push skips when remote is already at or above', () async {
    await logIn();
    http.queue.add(reply(fixtureText('fetch_entry')));
    await tracker.pushProgress('30104', 42);
    await tracker.pushProgress('30104', 0);
    expect(http.sent, hasLength(1));
  });

  test('push raises an existing entry without touching status', () async {
    await logIn();
    http.queue
      ..add(reply(fixtureText('fetch_entry')))
      ..add(reply(fixtureText('save_entry')));
    await tracker.pushProgress('30104', 43);
    expect(http.sent.last.json['query'], saveMutation);
    expect(http.sent.last.variables, {'mediaId': 30104, 'progress': 43});
  });

  test('push creates a missing entry as CURRENT', () async {
    await logIn();
    http.queue
      ..add(reply(fixtureText('fetch_no_entry')))
      ..add(reply(fixtureText('save_entry')));
    await tracker.pushProgress('30104', 3);
    expect(http.sent.last.variables, {
      'mediaId': 30104,
      'progress': 3,
      'status': 'CURRENT',
    });
  });

  test('push needs a login', () async {
    await expectLater(tracker.pushProgress('1', 1), throwsStateError);
    expect(http.sent, isEmpty);
  });

  test('an invalid token logs out and rethrows', () async {
    await logIn();
    http.queue.add(reply(fixtureText('invalid_token'), status: 400));
    await expectLater(tracker.fetch('30104'), throwsA(isA<AniListException>()));
    expect(await tracker.isLoggedIn(), isFalse);
  });

  test('other errors keep the login', () async {
    await logIn();
    for (var i = 0; i < 3; i++) {
      http.queue.add(reply(fixtureText('rate_limited'), status: 429));
    }
    await expectLater(tracker.search('x'), throwsA(isA<AniListException>()));
    expect(await tracker.isLoggedIn(), isTrue);
  });

  test('implements the §9 interface', () {
    expect(tracker, isA<Tracker>());
  });
}
