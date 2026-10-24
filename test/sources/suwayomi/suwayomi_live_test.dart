@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';

/// End to end against a real server, excluded by default (tag `live`):
/// `SUWAYOMI_URL=http://127.0.0.1:4599 SUWAYOMI_USER=kartka
/// SUWAYOMI_PASS=fixture fvm flutter test --run-skipped -t live
/// test/sources/suwayomi/suwayomi_live_test.dart`
/// (MangaDex extension installed on the server). SUWAYOMI_PASSWORD from
/// ~/.config/kartka/suwayomi.env works too.
class _IoHttp extends KartkaHttp {
  final _client = HttpClient();

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await _client.openUrl(method, url);
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (b, chunk) => b..add(chunk),
    );
    return KartkaResponse(
      statusCode: response.statusCode,
      bodyBytes: bytes.takeBytes(),
      headers: {'content-type': response.headers.contentType.toString()},
    );
  }
}

void main() {
  final env = Platform.environment;
  final url = env['SUWAYOMI_URL'];

  test('popular -> details -> chapters -> page image', () async {
    final http = _IoHttp();
    final store = SuwayomiSettingsStore(
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
    );
    await store.save(
      SuwayomiSettings(
        serverUrl: url!,
        username: env['SUWAYOMI_USER'] ?? '',
        password: env['SUWAYOMI_PASS'] ?? env['SUWAYOMI_PASSWORD'] ?? '',
      ),
    );
    final client = SuwayomiClient(http: http, settings: () => store.current!);
    expect(await client.testConnection(), startsWith('Suwayomi-Server'));
    final provider = SuwayomiSourceProvider(store: store, client: client);
    final sources = await provider.watch().first;
    final source = sources.firstWhere(
      (s) => s.ref.name == 'MangaDex' && s.ref.lang == 'en',
    );
    final manga = (await source.popular(1)).items.first;
    expect((await source.details(manga.url)).title, manga.title);
    final chapters = await source.chapters(manga.url);
    final pages = await source.pages(chapters.last.url);
    final image = await http.get(
      Uri.parse(pages.first.imageUrl),
      headers: pages.first.headers,
    );
    expect(image.statusCode, 200);
    expect(image.headers['content-type'], startsWith('image/'));
    await provider.dispose();
  }, skip: url == null ? 'set SUWAYOMI_URL' : false);
}
