// Live smoke test against the real MangaUpdates API: checks that the
// spec-built fixtures still match. Series search is public, so no account is
// needed. Excluded by default (dart_test.yaml skips `live`):
//   fvm flutter test --run-skipped --tags live test/tracking/mangaupdates
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/mangaupdates/mu_api.dart';
import 'package:kartka/tracking/mangaupdates/mu_client.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

/// Real network, test-only: `KartkaHttp` over package:http.
class _LiveHttp extends KartkaHttp {
  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final req = http.Request(method, url)
      ..headers.addAll({...headers, 'User-Agent': kartkaUserAgent});
    if (body != null) req.body = body;
    final res = await http.Response.fromStream(await req.send());
    return KartkaResponse(
      statusCode: res.statusCode,
      bodyBytes: res.bodyBytes,
      headers: res.headers,
    );
  }
}

void main() {
  test('search finds Berserk (series 51239621230) in the spec shape', () async {
    final api = MuApi(
      client: MuClient(http: _LiveHttp()),
      store: MuSessionStore(MemoryKeyValueStore()),
    );
    final hits = await api.search('Berserk');
    final berserk = hits.firstWhere((s) => s.id == 51239621230);
    expect(berserk.title, 'Berserk');
    expect(berserk.coverUrl, startsWith('https://'));
  });
}
