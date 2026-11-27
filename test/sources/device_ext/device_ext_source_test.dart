import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/net/network_errors.dart';
import 'package:kartka/core/source/manga_gone_error.dart';
import 'package:kartka/platform/memory/memory_extension_runtime.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/device_ext/device_ext_api.dart';
import 'package:kartka/sources/device_ext/device_ext_source.dart';

const info = DeviceSourceInfo(
  id: '6084907896154116083',
  name: 'MangaFire',
  lang: 'en',
  supportsLatest: true,
);

Object? answer(String m, Map<String, Object?> a) => switch (m) {
  'popular' || 'latest' || 'search' => {
    'mangas': [
      {'url': '/m/1', 'title': 'One', 'thumbnailUrl': 'https://c/1.jpg'},
      {'url': '/m/2', 'title': 'Two', 'thumbnailUrl': ' '},
    ],
    'hasNextPage': true,
  },
  'details' => {
    'url': a['url'],
    'title': 'One',
    'thumbnailUrl': 'https://c/1.jpg',
    'author': 'A, B',
    'artist': 'B',
    'description': 'About',
    'genre': 'Action, Drama',
    'status': 2,
  },
  'chapters' => [
    {'url': '/c/2', 'name': 'Ch 2', 'number': 2.0, 'dateUpload': 1000},
    {'url': '/c/x', 'name': 'Extra', 'number': -1.0, 'dateUpload': 0},
  ],
  'pages' => [
    {'index': 0, 'url': '', 'imageUrl': 'https://i/0.jpg'},
    {'index': 1, 'url': '/p/1', 'imageUrl': null},
  ],
  _ => null,
};

void main() {
  final runtime = FakeExtensionRuntime(
    handler: answer,
    images: {
      'https://i/0.jpg': Uint8List.fromList([9]),
    },
  );
  final source = DeviceExtSource(info: info, runtime: runtime);

  test('shares the suwayomi id space and maps listings', () async {
    expect(source.ref.id, 'suwayomi:6084907896154116083');
    expect(source.ref.origin, SourceOrigin.suwayomi);
    final page = await source.popular(1);
    expect(page.hasNext, isTrue);
    expect(page.items.first.coverUrl, startsWith('kartka-ext://source/'));
    expect(page.items.last.coverUrl, isNull);
    expect((await source.latest(2)).items, hasLength(2));
    expect((await source.search('one', 1)).items.first.url, '/m/1');
    expect(runtime.calls.last.$2, {'id': info.id, 'page': 1, 'query': 'one'});
    final noLatest = DeviceExtSource(
      info: const DeviceSourceInfo(
        id: '1',
        name: 'x',
        lang: 'en',
        supportsLatest: false,
      ),
      runtime: runtime,
    );
    expect(await noLatest.latest(1), SearchPage.empty);
  });

  test('maps details, chapters and pages', () async {
    final d = await source.details('/m/1');
    expect(d.authors, ['A', 'B']);
    expect(d.genres, ['Action', 'Drama']);
    expect(d.status, MangaStatus.completed);
    expect(d.description, 'About');
    final chapters = await source.chapters('/m/1');
    expect(chapters.first.number, 2);
    expect(chapters.first.uploadedAt!.millisecondsSinceEpoch, 1000);
    expect(chapters.last.number, isNull);
    expect(chapters.last.uploadedAt, isNull);
    final pages = await source.pages('/c/2');
    expect(pages.map((p) => p.index), [0, 1]);
    final loader = PageImageLoader(
      http: FakeKartkaHttp(),
      blobs: MemoryBlobStore(),
      extensions: runtime,
    );
    expect(await loader.load(pages.first), [9]);
    await expectLater(
      PageImageLoader(
        http: FakeKartkaHttp(),
        blobs: MemoryBlobStore(),
      ).load(pages.first),
      throwsArgumentError,
    );
  });

  test('an unknown status code reads as unknown', () async {
    final odd = DeviceExtSource(
      info: info,
      runtime: FakeExtensionRuntime(
        handler: (m, a) => {'title': 'T', 'status': 42},
      ),
    );
    expect((await odd.details('/m')).status, MangaStatus.unknown);
  });

  test('a manga the site refuses (404, 410, 451) is gone (4c696ac8)', () async {
    DeviceExtSource failing(String text) => DeviceExtSource(
      info: info,
      runtime: FakeExtensionRuntime(
        handler: (m, a) => throw ExtensionRuntimeException(text),
      ),
    );
    for (final code in [404, 410, 451]) {
      final s = failing('HTTP error $code');
      await expectLater(s.chapters('/m'), throwsA(isA<MangaGoneError>()));
      await expectLater(s.details('/m'), throwsA(isA<MangaGoneError>()));
    }
    // Every screen skips a gone manga; a path that logs it anyway is an
    // environment state, never a board ticket (as Suwayomi's own text).
    const gone = DeviceExtMangaGone(
      'suwayomi:2327480808438768017',
      ExtensionRuntimeException('HTTP error 451'),
    );
    expect(isEnvironmentError(gone), isTrue);
    final down = failing('HTTP error 500');
    await expectLater(
      down.chapters('/m'),
      throwsA(isA<ExtensionRuntimeException>()),
    );
    await expectLater(
      failing('HTTP error 451').popular(1),
      throwsA(isA<ExtensionRuntimeException>()),
    );
  });
}
