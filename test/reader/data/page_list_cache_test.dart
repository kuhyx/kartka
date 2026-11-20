import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/page_list_cache.dart';

import '../support/fakes.dart';

/// A source whose page list fails like AllManga on Suwayomi v2.4.2366.
class _WebViewSource extends FakeSource {
  new({
    super.id,
    super.pageMap,
    this.name = 'Fake',
    this.origin = SourceOrigin.native,
  });

  final String name;
  final SourceOrigin origin;
  bool broken = true;
  Completer<void>? gate;

  @override
  SourceRef get ref =>
      SourceRef(id: id, name: name, lang: 'en', origin: origin);

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    pageCalls.add(chapterUrl);
    await gate?.future;
    if (broken) {
      throw Exception('keiyoushi.b.G: Timed out waiting for WebView after 20s');
    }
    return pageMap[chapterUrl]!;
  }
}

/// reader.open waited 20 s on a WebView the server cannot run (971debc8):
/// the cache remembers that, and keeps page lists fetched ahead.
void main() {
  late MemoryKeyValueStore kv;
  late DateTime now;
  late PageListCache cache;

  setUp(() {
    kv = MemoryKeyValueStore();
    now = DateTime.utc(2026, 11, 19, 12);
    cache = PageListCache(kv, now: () => now);
  });

  test('a fetched list is served again without asking the source', () async {
    final src = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 2)});
    expect(await cache.pages(src, '/c/1'), hasLength(2));
    expect(await cache.pages(src, '/c/1'), hasLength(2));
    expect(src.pageCalls, ['/c/1']);
  });

  test('a kept list expires, and fresh always asks', () async {
    final src = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 2)});
    await cache.pages(src, '/c/1');
    await cache.pages(src, '/c/1', fresh: true);
    expect(src.pageCalls, hasLength(2));
    now = now.add(PageListCache.keep + const Duration(seconds: 1));
    await cache.pages(src, '/c/1');
    expect(src.pageCalls, hasLength(3));
  });

  test('a fetch in flight is shared, never sent twice', () async {
    final src = _WebViewSource(pageMap: {'/c/1': fakePages('/c/1', 2)})
      ..broken = false
      ..gate = Completer<void>();
    cache.warm(src, '/c/1');
    final open = cache.pages(src, '/c/1');
    src.gate!.complete();
    expect(await open, hasLength(2));
    expect(src.pageCalls, ['/c/1']);
  });

  test('a WebView timeout marks the source: the next open fails at once, '
      'on every chapter, across restarts', () async {
    final src = _WebViewSource();
    await expectLater(cache.pages(src, '/c/1'), throwsException);
    final restarted = PageListCache(kv, now: () => now);
    await expectLater(
      restarted.pages(src, '/c/2'),
      throwsA(isA<SourceNeedsWebView>()),
    );
    expect(src.pageCalls, ['/c/1'], reason: 'the marked source is not asked');
  });

  test('a Retry in flight on a marked source: reopening fails at once, '
      'never joins its 20 s fetch', () async {
    final src = _WebViewSource()..gate = Completer<void>();
    await kv.set('${PageListCache.markPrefix}fake', 'x');
    final retry = cache.pages(src, '/c/1', fresh: true);
    await expectLater(
      cache.pages(src, '/c/1').timeout(const Duration(seconds: 1)),
      throwsA(isA<SourceNeedsWebView>()),
    );
    src.gate!.complete();
    await expectLater(retry, throwsException);
  });

  test('a warm-up failure is swallowed but still marks the source', () async {
    final src = _WebViewSource()..gate = Completer<void>();
    cache.warm(src, '/c/1');
    src.gate!.complete();
    await pumpEventQueue();
    await expectLater(
      cache.pages(src, '/c/1'),
      throwsA(isA<SourceNeedsWebView>()),
    );
  });

  test('fresh asks a marked source; success clears the mark', () async {
    final src = _WebViewSource(
      pageMap: {'/c/1': fakePages('/c/1', 2), '/c/2': fakePages('/c/2', 1)},
    );
    await expectLater(cache.pages(src, '/c/1'), throwsException);
    src.broken = false;
    expect(await cache.pages(src, '/c/1', fresh: true), hasLength(2));
    expect(await cache.pages(src, '/c/2'), hasLength(1));
    expect(await kv.entries(prefix: PageListCache.markPrefix), isEmpty);
  });

  test('the mark never lapses', () async {
    final src = _WebViewSource();
    await expectLater(cache.pages(src, '/c/1'), throwsException);
    now = now.add(const Duration(days: 400));
    await expectLater(
      cache.pages(src, '/c/1'),
      throwsA(isA<SourceNeedsWebView>()),
    );
    expect(src.pageCalls, ['/c/1']);
  });

  test('other failures are not remembered', () async {
    final src = FakeSource();
    await expectLater(cache.pages(src, '/c/1'), throwsStateError);
    await expectLater(cache.pages(src, '/c/1'), throwsStateError);
    expect(src.pageCalls, hasLength(2));
  });

  test('any stored mark counts, also a lapsed legacy expiry', () async {
    for (final value in ['garbage', '2026-01-01T00:00:00.000Z']) {
      await kv.set('${PageListCache.markPrefix}fake', value);
      final src = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 1)});
      await expectLater(
        cache.pages(src, '/c/1'),
        throwsA(isA<SourceNeedsWebView>()),
      );
      expect(src.pageCalls, isEmpty);
      await kv.remove('${PageListCache.markPrefix}fake');
    }
  });

  test('AllManga on Suwayomi starts marked, without a fetch', () async {
    final src = _WebViewSource(name: 'AllManga', origin: SourceOrigin.suwayomi);
    await expectLater(
      cache.pages(src, '/c/1'),
      throwsA(isA<SourceNeedsWebView>()),
    );
    expect(src.pageCalls, isEmpty);
    // A native-origin AllManga with a working pageMap is not seeded.
    final nat = _WebViewSource(
      id: 'native-allmanga',
      name: 'AllManga',
      pageMap: {'/c/1': fakePages('/c/1', 1)},
    )..broken = false;
    expect(await cache.pages(nat, '/c/1'), hasLength(1));
  });

  test(
    'a fresh success unseeds AllManga for good, also after a restart',
    () async {
      final src = _WebViewSource(
        id: 'suwayomi-allmanga',
        name: 'AllManga',
        origin: SourceOrigin.suwayomi,
        pageMap: {'/c/1': fakePages('/c/1', 2), '/c/2': fakePages('/c/2', 1)},
      )..broken = false;
      expect(await cache.pages(src, '/c/1', fresh: true), hasLength(2));
      expect(
        await kv.get('${PageListCache.okPrefix}suwayomi-allmanga'),
        isNotNull,
      );
      expect(await cache.pages(src, '/c/2'), hasLength(1));
      expect(
        await kv.get('${PageListCache.markPrefix}suwayomi-allmanga'),
        isNull,
      );
      final restarted = PageListCache(kv, now: () => now);
      expect(await restarted.pages(src, '/c/2'), hasLength(1));
    },
  );
}
