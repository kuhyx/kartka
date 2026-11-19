import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/page_list_cache.dart';

import '../support/fakes.dart';

/// A source whose page list fails like AllManga on Suwayomi v2.4.2366.
class _WebViewSource extends FakeSource {
  new({super.pageMap});

  bool broken = true;
  Completer<void>? gate;

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

  test('the mark expires', () async {
    final src = _WebViewSource();
    await expectLater(cache.pages(src, '/c/1'), throwsException);
    now = now.add(PageListCache.brokenFor + const Duration(seconds: 1));
    await expectLater(
      cache.pages(src, '/c/1'),
      throwsA(isNot(isA<SourceNeedsWebView>())),
    );
    expect(src.pageCalls, hasLength(2));
  });

  test('other failures are not remembered', () async {
    final src = FakeSource();
    await expectLater(cache.pages(src, '/c/1'), throwsStateError);
    await expectLater(cache.pages(src, '/c/1'), throwsStateError);
    expect(src.pageCalls, hasLength(2));
  });

  test('an unreadable mark counts as none', () async {
    await kv.set('${PageListCache.markPrefix}fake', 'garbage');
    final src = FakeSource(pageMap: {'/c/1': fakePages('/c/1', 1)});
    expect(await cache.pages(src, '/c/1'), hasLength(1));
  });
}
