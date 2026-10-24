import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

class _Referer implements ImageHeaders {
  @override
  Map<String, String> forUrl(String url) =>
      url.contains('cdn') ? {'Referer': 'https://site/', 'X-A': 'a'} : {};
}

void main() {
  late FakeKartkaHttp http;
  late MemoryBlobStore blobs;
  late PageImageLoader loader;

  setUp(() {
    http = FakeKartkaHttp(
      (r) => r.url.path == '/missing'
          ? FakeKartkaHttp.text('', status: 404)
          : KartkaResponse(statusCode: 200, bodyBytes: Uint8List(3)),
    );
    blobs = MemoryBlobStore();
    loader = PageImageLoader(
      http: http,
      blobs: blobs,
      imageHeaders: [_Referer()],
    );
  });

  test('blobPageUrl builds the kartka-blob scheme and checks the key', () {
    expect(blobPageUrl('pages/a/1'), 'kartka-blob://pages/a/1');
    expect(() => blobPageUrl('../x'), throwsArgumentError);
  });

  test('kartka-blob pages come from the BlobStore', () async {
    await blobs.put('pages/a/1', Uint8List.fromList([5]));
    final page = PageRef(index: 0, imageUrl: blobPageUrl('pages/a/1'));
    expect(await loader.load(page), [5]);
    expect(http.requests, isEmpty);
  });

  test('a missing or invalid blob is an error', () async {
    await expectLater(
      loader.load(const PageRef(index: 0, imageUrl: 'kartka-blob://nope')),
      throwsStateError,
    );
    await expectLater(
      loader.load(const PageRef(index: 0, imageUrl: 'kartka-blob://../x')),
      throwsArgumentError,
    );
  });

  test('http(s) pages merge provider headers, the page wins', () async {
    const page = PageRef(
      index: 0,
      imageUrl: 'https://cdn.example/1.jpg',
      headers: {'X-A': 'page'},
    );
    expect(await loader.load(page), hasLength(3));
    expect(http.requests.single.headers, {
      'Referer': 'https://site/',
      'X-A': 'page',
    });
  });

  test('non-2xx and unknown schemes throw', () async {
    await expectLater(
      loader.load(const PageRef(index: 0, imageUrl: 'http://h/missing')),
      throwsA(isA<KartkaHttpException>()),
    );
    await expectLater(
      loader.load(const PageRef(index: 0, imageUrl: 'ftp://h/x')),
      throwsArgumentError,
    );
  });

  test('blob keys: segments of [A-Za-z0-9._-], no dot segments', () {
    expect(isValidBlobKey('pages/abc/001.jpg'), isTrue);
    for (final bad in ['', '/a', 'a/', 'a//b', '.', 'a/../b', 'a b', 'ż']) {
      expect(isValidBlobKey(bad), isFalse, reason: bad);
    }
    expect(
      KartkaHttpException(Uri(host: 'h'), 500).toString(),
      contains('500'),
    );
    expect(const OAuthCancelled().toString(), 'OAuthCancelled');
  });
}
