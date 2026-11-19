import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/page_list_cache.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';

import '../../sources/suwayomi/fakes.dart';

const _allManga = '4709139914729853090';

/// The live server's answer for an AllManga chapter on v2.4.2366, captured
/// 2026-11-19 after 20.8 s (971debc8), stack cut.
final String _webView = jsonEncode({
  'data': {'fetchChapterPages': null},
  'errors': [
    {
      'message':
          'Exception while fetching data (/fetchChapterPages) : Timed out '
          'waiting for WebView after 20s\r\n\r\nkeiyoushi.b.G: Timed out '
          'waiting for WebView after 20s\n\tat keiyoushi.b.z.invokeSuspend',
    },
  ],
});

final String _chapterId = jsonEncode({
  'data': {
    'chapters': {
      'nodes': [
        {
          'id': 161,
          'manga': {'sourceId': _allManga},
        },
      ],
    },
  },
});

/// The mark is set from what the real client throws, not a test string.
void main() {
  test('a Suwayomi WebView timeout marks the source', () async {
    final sent = <String>[];
    final source = SuwayomiSource(
      info: const SuwayomiSourceInfo(
        serverId: _allManga,
        ref: SourceRef(
          id: 'suwayomi:$_allManga',
          name: 'AllManga',
          lang: 'en',
          origin: SourceOrigin.suwayomi,
        ),
        supportsLatest: true,
      ),
      client: SuwayomiClient(
        http: FakeKartkaHttp((r) {
          sent.add(r.body!);
          return FakeKartkaHttp.text(
            r.body!.contains('KartkaPages') ? _webView : _chapterId,
          );
        }),
        settings: () => fixtureSettings,
      ),
      settings: () => fixtureSettings,
    );
    final cache = PageListCache(MemoryKeyValueStore());
    await expectLater(cache.pages(source, '/chapter/1'), throwsException);
    await expectLater(
      cache.pages(source, '/chapter/2'),
      throwsA(isA<SourceNeedsWebView>()),
    );
    expect(sent.where((b) => b.contains('KartkaPages')), hasLength(1));
  });
}
