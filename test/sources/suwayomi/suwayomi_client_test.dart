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
    final http = fixtureHttp(['about']);
    expect(await client(http).testConnection(), 'Suwayomi-Server v2.4.2366');
    expect(bodies(http).single, {
      'operationName': 'KartkaAbout',
      'query': SuwayomiQueries.about,
      'variables': <String, Object?>{},
    });
    expect(
      http.requests.single.headers['Authorization'],
      'Basic a2FydGthOmZpeHR1cmU=',
    );
    expect(http.requests.single.headers['Content-Type'], 'application/json');
  });

  test('a 401 is an auth failure', () {
    final http = fixtureHttp(['unauthorized']);
    expect(
      () => client(http).testConnection(),
      throwsA(isA<SuwayomiAuthException>()),
    );
  });

  test('GraphQL errors keep only the first line', () {
    expect(
      () =>
          client(cannedHttp(200, r'{"errors":[{"message":"boom\r\nat x"}]}'))
              .run(SuwayomiQueries.about),
      throwsA(
        isA<SuwayomiException>().having((e) => e.message, 'message', 'boom'),
      ),
    );
    expect(
      () =>
          client(cannedHttp(200, '{"errors":["flat"]}'))
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
      () => client(cannedHttp(502, 'bad gateway')).run(SuwayomiQueries.about),
      fails('HTTP 502'),
    );
    expect(
      () => client(cannedHttp(200, '<html>')).run(SuwayomiQueries.about),
      fails('not a GraphQL response'),
    );
    expect(
      () => client(cannedHttp(200, '[1]')).run(SuwayomiQueries.about),
      fails('not a GraphQL response'),
    );
    expect(
      () => client(cannedHttp(200, '{"data":null}')).run(SuwayomiQueries.about),
      fails('response has no data'),
    );
  });

  test('nothing is sent before a server URL is configured', () {
    final http = fixtureHttp([]);
    expect(
      () => client(http, const SuwayomiSettings()).testConnection(),
      throwsA(isA<SuwayomiNotConfiguredException>()),
    );
    expect(bodies(http), isEmpty);
  });

  test('exceptions describe themselves', () {
    expect(
      SuwayomiNotOnServerException('suwayomi:1', '/manga/x').toString(),
      'SuwayomiException: /manga/x is not on the server for suwayomi:1',
    );
  });
}
