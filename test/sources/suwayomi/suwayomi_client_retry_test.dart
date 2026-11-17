import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';

import 'fakes.dart';

const _abort = 'ClientException: Software caused connection abort, uri=x';
const _webView =
    '{"errors":[{"message":"Exception while fetching data '
    '(/fetchChapterPages) : Timed out waiting for WebView after 20s"}]}';
const _ok = '{"data":{"aboutServer":{"name":"S","version":"1"}}}';

/// One dropped connection or one upstream WebView timeout is retried once
/// silently (bcbad5dd, 2d4a35c2); a second failure, or one of an
/// operation that changes the server, still throws.
void main() {
  (SuwayomiClient, List<String>) client(List<Object> answers) {
    final calls = <String>[];
    final http = FakeKartkaHttp((request) {
      calls.add(request.body!);
      final next = answers.removeAt(0);
      if (next is Exception) throw next;
      return FakeKartkaHttp.text('$next');
    });
    return (
      SuwayomiClient(
        http: http,
        settings: () => fixtureSettings,
        retryDelay: Duration.zero,
      ),
      calls,
    );
  }

  test('a dropped connection is retried once', () async {
    final (c, calls) = client([Exception(_abort), _ok]);
    expect(await c.testConnection(), 'S 1');
    expect(calls, hasLength(2));
  });

  test('a WebView timeout is retried once', () async {
    final (c, calls) = client([_webView, _ok]);
    expect(await c.testConnection(), 'S 1');
    expect(calls, hasLength(2));
  });

  test('a second failure throws', () async {
    final (c, calls) = client([_webView, _webView]);
    await expectLater(c.testConnection(), throwsA(isA<SuwayomiException>()));
    expect(calls, hasLength(2));
  });

  test('other errors and server-changing operations are not retried', () async {
    final (c, calls) = client(['{"errors":["boom"]}']);
    await expectLater(c.testConnection(), throwsA(isA<SuwayomiException>()));
    expect(calls, hasLength(1));
    final (u, uCalls) = client([Exception(_abort)]);
    await expectLater(
      u.run(SuwayomiQueries.updateExtension, {'id': 'a'}),
      throwsA(isA<Exception>()),
    );
    expect(uCalls, hasLength(1));
  });
}
