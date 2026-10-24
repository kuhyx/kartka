import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/mangadex/mangadex_image_headers.dart';

void main() {
  const h = MangadexImageHeaders();

  test('MangaDex cover and page hosts get the User-Agent', () {
    for (final url in [
      'https://uploads.mangadex.org/covers/a/b.jpg.512.jpg',
      'https://cmdxd98sb0x3yprd.mangadex.network/data/h/f.jpg',
      'https://mangadex.org/x',
    ]) {
      expect(h.forUrl(url), {'User-Agent': kartkaUserAgent}, reason: url);
    }
  });

  test('other hosts and garbage get nothing', () {
    expect(h.forUrl('https://example.com/a.jpg'), isEmpty);
    expect(h.forUrl('https://evilmangadex.org/a.jpg'), isEmpty);
    expect(h.forUrl('::not a url'), isEmpty);
  });
}
