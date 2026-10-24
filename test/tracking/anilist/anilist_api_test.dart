import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/anilist/anilist_api.dart';
import 'package:kartka/tracking/anilist/anilist_parse.dart';
import 'package:kartka/tracking/anilist/anilist_queries.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';

import '../fakes.dart';

void main() {
  late FakeHttp http;
  late List<Duration> waits;
  late AniListApi api;

  setUp(() {
    http = FakeHttp();
    waits = [];
    api = AniListApi(
      http,
      limiter: RateLimiter(
        perMinute: 30,
        minGap: Duration.zero,
        sleep: (d) async => waits.add(d),
      ),
    );
  });

  test('posts query, variables and bearer token as JSON', () async {
    http.queue.add(reply(fixtureText('search_yotsuba')));
    final body = await api.call(searchQuery, {'search': 'x'}, token: 'T');
    final sent = http.sent.single;
    expect(sent.url, aniListEndpoint);
    expect(sent.headers['Authorization'], 'Bearer T');
    expect(sent.headers['Content-Type'], 'application/json');
    expect(sent.json['query'], searchQuery);
    expect(sent.variables, {'search': 'x'});
    expect(parseSearch(body), hasLength(5));
  });

  test('anonymous calls carry no Authorization header', () async {
    http.queue.add(reply(fixtureText('search_empty')));
    await api.call(searchQuery, {'search': 'x'});
    expect(http.sent.single.headers.containsKey('Authorization'), isFalse);
  });

  test('429 waits Retry-After and retries', () async {
    http.queue
      ..add(
        reply(
          fixtureText('rate_limited'),
          status: 429,
          headers: {'retry-after': '30', 'x-ratelimit-remaining': '0'},
        ),
      )
      ..add(reply(fixtureText('save_entry')));
    final body = await api.call(saveMutation, {'mediaId': 1});
    expect(parseSaved(body), 43);
    expect(http.sent, hasLength(2));
    expect(waits.single, greaterThanOrEqualTo(const Duration(seconds: 30)));
  });

  test('gives up after maxRetries and surfaces the 429 error', () async {
    for (var i = 0; i < 3; i++) {
      http.queue.add(reply(fixtureText('rate_limited'), status: 429));
    }
    final body = await api.call(fetchQuery, {'id': 1});
    expect(http.sent, hasLength(3));
    expect(
      () => parseFetch(body),
      throwsA(
        isA<AniListException>().having((e) => e.isRateLimited, 'r', true),
      ),
    );
  });

  test('400 Invalid token body is returned for the parser', () async {
    http.queue.add(reply(fixtureText('invalid_token'), status: 400));
    final body = await api.call(fetchQuery, {'id': 1}, token: 'bad');
    expect(
      () => parseFetch(body),
      throwsA(isA<AniListException>().having((e) => e.isAuthError, 'a', true)),
    );
  });

  test('a non-JSON body is an AniListException with the status', () async {
    http.queue.add(reply('<html>bad gateway</html>', status: 502));
    expect(
      api.call(fetchQuery, {'id': 1}),
      throwsA(isA<AniListException>().having((e) => e.status, 's', 502)),
    );
  });

  test('a JSON non-object body is an AniListException', () async {
    http.queue.add(reply('[1]'));
    expect(api.call(fetchQuery, {}), throwsA(isA<AniListException>()));
  });

  test('default limiter allows 30 per minute', () {
    expect(AniListApi(http).limiter.perMinute, 30);
  });
}
