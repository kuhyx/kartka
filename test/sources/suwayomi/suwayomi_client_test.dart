import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

import 'fakes.dart';

void main() {
  SuwayomiClient client(
    KartkaHttp http, [
    SuwayomiSettings settings = fixtureSettings,
  ]) => SuwayomiClient(http: http, settings: () => settings);

  test('posts operationName, query and variables with basic auth', () async {
    final http = FixtureHttp(['about']);
    expect(await client(http).testConnection(), 'Suwayomi-Server v2.4.2366');
    expect(http.requests.single, {
      'operationName': 'KartkaAbout',
      'query': SuwayomiQueries.about,
      'variables': <String, Object?>{},
    });
    expect(http.headers.single['Authorization'], 'Basic a2FydGthOmZpeHR1cmU=');
    expect(http.headers.single['Content-Type'], 'application/json');
  });

  test('a 401 is an auth failure', () {
    final http = FixtureHttp(['unauthorized']);
    expect(
      () => client(http).testConnection(),
      throwsA(isA<SuwayomiAuthException>()),
    );
  });

  test('GraphQL errors keep only the first line', () {
    expect(
      () => client(CannedHttp(200, '{"errors":[{"message":"boom\\r\\nat x"}]}'))
          .run(SuwayomiQueries.about),
      throwsA(
        isA<SuwayomiException>().having((e) => e.message, 'message', 'boom'),
      ),
    );
    expect(
      () => client(CannedHttp(200, '{"errors":["flat"]}'))
          .run(SuwayomiQueries.about),
      throwsA(
        isA<SuwayomiException>().having((e) => e.message, 'message', 'flat'),
      ),
    );
  });

  test('non-2xx, non-JSON and data-less answers fail', () {
    Matcher fails(String message) => throwsA(
      isA<SuwayomiException>().having((e) => e.message, 'message', message),
    );
    expect(
      () => client(CannedHttp(502, 'bad gateway')).run(SuwayomiQueries.about),
      fails('HTTP 502'),
    );
    expect(
      () => client(CannedHttp(200, '<html>')).run(SuwayomiQueries.about),
      fails('not a GraphQL response'),
    );
    expect(
      () => client(CannedHttp(200, '[1]')).run(SuwayomiQueries.about),
      fails('not a GraphQL response'),
    );
    expect(
      () => client(CannedHttp(200, '{"data":null}')).run(SuwayomiQueries.about),
      fails('response has no data'),
    );
  });

  test('nothing is sent before a server URL is configured', () {
    final http = FixtureHttp([]);
    expect(
      () => client(http, const SuwayomiSettings()).testConnection(),
      throwsA(isA<SuwayomiNotConfiguredException>()),
    );
    expect(http.requests, isEmpty);
  });

  test('exceptions describe themselves', () {
    expect(
      SuwayomiNotOnServerException('suwayomi:1', '/manga/x').toString(),
      'SuwayomiException: /manga/x is not on the server for suwayomi:1',
    );
  });
}
