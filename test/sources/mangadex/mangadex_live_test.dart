@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';

import 'fakes.dart';

/// Minimal dart:io client; test-only, so lib/ stays free of dart:io.
class _IoHttp extends KartkaHttp {
  final _client = HttpClient();

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final req = await _client.openUrl(method, url);
    headers.forEach(req.headers.set);
    final res = await req.close();
    final bytes = await res.fold<BytesBuilder>(
      BytesBuilder(),
      (b, chunk) => b..add(chunk),
    );
    return KartkaResponse(
      statusCode: res.statusCode,
      bodyBytes: bytes.takeBytes(),
      headers: _flat(res.headers),
    );
  }

  static Map<String, String> _flat(HttpHeaders h) {
    final out = <String, String>{};
    h.forEach((name, values) => out[name] = values.join(','));
    return out;
  }
}

void main() {
  test('live: popular -> details -> chapters -> pages', () async {
    final s = MangaDexSource(
      http: _IoHttp(),
      settings: MangadexSettingsStore(FakeKv()),
    );
    final popular = await s.popular(1);
    expect(popular.items, isNotEmpty);
    final details = await s.details(popular.items.first.url);
    expect(details.title, isNotEmpty);
    // Licensed titles can list no hosted chapters; take the first that has.
    var chapters = const <ChapterInfo>[];
    for (final manga in popular.items.take(5)) {
      chapters = await s.chapters(manga.url);
      if (chapters.isNotEmpty) break;
    }
    expect(chapters, isNotEmpty);
    final pages = await s.pages(chapters.last.url);
    expect(pages, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
