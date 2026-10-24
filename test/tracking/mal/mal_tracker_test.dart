import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_tracker.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

MalTracker _tracker(FakeTransport http, MemoryTokenStore store) => MalTracker(
  auth: MalAuth(
    client: const MalOAuthClient(clientId: 'cid', redirectUri: 'x://y'),
    send: http.send,
    store: store,
    launch: (a) async =>
        Uri.parse('x://y?code=c&state=${a.queryParameters['state']}'),
    random: Random(3),
    now: () => testNow,
  ),
  store: store,
  api: buildApi(http, store),
);

/// Remote entry JSON with [read] chapters (absent from the list when null).
String _entry({int? read, String status = 'reading', int total = 0}) =>
    jsonEncode({
      'id': 7,
      'title': 'T',
      'num_chapters': total,
      if (read != null)
        'my_list_status': {
          'status': status,
          'num_chapters_read': read,
          'score': 0,
        },
    });

MalResponse _byMethod(MalRequest r, String entry) => switch (r.method) {
  MalMethod.get => MalResponse(200, entry),
  _ => fx(200, 'list_status_updated.json'),
};

void main() {
  late FakeTransport http;
  late MemoryTokenStore store;
  late Tracker tracker;

  setUp(() {
    http = FakeTransport((_) => fx(200, 'token_ok.json'));
    store = MemoryTokenStore();
    tracker = _tracker(http, store);
  });

  test('identity', () {
    expect(tracker.id, 'mal');
    expect(tracker.name, 'MyAnimeList');
  });

  test('login, isLoggedIn, logout', () async {
    expect(await tracker.isLoggedIn(), isFalse);
    await tracker.login();
    expect(await tracker.isLoggedIn(), isTrue);
    await tracker.logout();
    expect(await tracker.isLoggedIn(), isFalse);
  });

  test('search maps to TrackSearchResult', () async {
    http.handler = (_) => fx(200, 'search_berserk.json');
    final hits = await tracker.search('Berserk');
    expect(hits.first.remoteId, '2');
    expect(hits.first.chapters, isNull);
    expect(hits.last.chapters, 1);
  });

  group('fetch', () {
    setUp(() => store.tokens = validTokens());

    test('maps the list entry', () async {
      http.handler = (_) => fx(200, 'manga_finished.json');
      expect(
        await tracker.fetch('25'),
        const TrackStatus(
          remoteId: '25',
          chaptersRead: 10,
          totalChapters: 116,
          status: 'plan_to_read',
          score: 9,
        ),
      );
    });

    test('not on the list or unknown id is null', () async {
      http.handler = (_) => fx(200, 'manga_not_listed.json');
      expect(await tracker.fetch('44347'), isNull);
      http.handler = (_) => const MalResponse(404, '');
      expect(await tracker.fetch('1'), isNull);
    });

    test('non-numeric remote id is rejected', () {
      expect(() => tracker.fetch('abc'), throwsArgumentError);
    });
  });

  group('pushProgress', () {
    setUp(() => store.tokens = validTokens());

    Future<Map<String, String>?> push(int n, String entry) async {
      http.handler = (r) => _byMethod(r, entry);
      await tracker.pushProgress('7', n);
      final patches = http.withMethod(MalMethod.patch);
      return patches.isEmpty
          ? null
          : Uri.splitQueryString(patches.single.body!);
    }

    test('no PATCH when remote is ahead or equal', () async {
      expect(await push(5, _entry(read: 9)), isNull);
      http.requests.clear();
      expect(await push(9, _entry(read: 9)), isNull);
    });

    test('raises progress without touching status', () async {
      expect(await push(12, _entry(read: 9)), {'num_chapters_read': '12'});
    });

    test('adds a missing entry as reading', () async {
      expect(await push(3, _entry()), {
        'num_chapters_read': '3',
        'status': 'reading',
      });
    });

    test('zero chapters on a missing entry is a no-op', () async {
      expect(await push(0, _entry()), isNull);
    });

    test('plan_to_read becomes reading', () async {
      expect(await push(2, _entry(read: 0, status: 'plan_to_read')), {
        'num_chapters_read': '2',
        'status': 'reading',
      });
    });

    test('on_hold and dropped keep their status', () async {
      expect(await push(4, _entry(read: 1, status: 'on_hold')), {
        'num_chapters_read': '4',
      });
    });

    test('reaching the total completes and clamps', () async {
      expect(await push(130, _entry(read: 100, total: 116)), {
        'num_chapters_read': '116',
        'status': 'completed',
      });
    });

    test('clamped value not above remote is a no-op', () async {
      expect(await push(130, _entry(read: 116, total: 116)), isNull);
    });

    glados.Glados2(
      glados.any.intInRange(0, 2000),
      glados.any.intInRange(0, 2000),
    ).test('never lowers the remote count', (remote, local) async {
      http.requests.clear();
      final sent = await push(local, _entry(read: remote));
      if (local <= remote) {
        expect(sent, isNull);
      } else {
        expect(int.parse(sent!['num_chapters_read']!), local);
      }
    });
  });

  test('malNextStatus table', () {
    expect(
      malNextStatus(current: null, chaptersRead: 1, total: null),
      'reading',
    );
    expect(
      malNextStatus(current: 'completed', chaptersRead: 5, total: 5),
      null,
    );
    expect(
      malNextStatus(current: 'dropped', chaptersRead: 5, total: 5),
      'completed',
    );
    expect(malNextStatus(current: 'reading', chaptersRead: 4, total: 5), null);
  });
}
