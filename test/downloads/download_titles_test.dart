import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/downloads/download_titles.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import 'fakes.dart';
import 'service_harness.dart';

void main() {
  test('asks the source once, then answers from the kv cache', () async {
    final kv = MemoryKeyValueStore();
    final source = FakeSource()..title = 'Berserk';
    Future<MangaSource?> find(String id) async =>
        id == 'mangadex' ? source : null;
    final titles = DownloadTitles(kv: kv, findSource: find);
    expect(await titles.title(mangaKey), 'Berserk');
    expect(await titles.title(mangaKey), 'Berserk');
    expect(source.detailCalls, 1);
    // A later launch (fresh instance) needs no network: works offline.
    final again = DownloadTitles(
      kv: kv,
      findSource: (_) async => throw StateError('offline'),
    );
    expect(await again.title(mangaKey), 'Berserk');
  });

  test('null when the source is missing or fails; a failure retries', () async {
    final kv = MemoryKeyValueStore();
    final source = FakeSource();
    final titles = DownloadTitles(kv: kv, findSource: (_) async => source);
    expect(await titles.title(mangaKey), isNull); // details() throws
    source.title = 'Berserk';
    expect(await titles.title(mangaKey), 'Berserk');
    final none = DownloadTitles(kv: kv, findSource: (_) async => null);
    expect(await none.title('mangadex|/other'), isNull);
  });
}
