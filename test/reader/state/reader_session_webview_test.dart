import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/page_list_cache.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// A source whose page lists time out on a WebView until [broken] is off.
class _WebView extends FakeSource {
  new() : super(chapterList: sessionChapters);

  bool broken = true;

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    pageCalls.add(chapterUrl);
    if (broken) throw Exception('Timed out waiting for WebView after 20s');
    return fakePages(chapterUrl, 3);
  }
}

/// A source marked as needing a WebView fails the open at once, writes no
/// `reader.open` failure, and Retry (fresh) asks it again (971debc8).
void main() {
  late SessionFixture f;
  late PageListCache cache;
  late _WebView src;

  setUp(() async {
    f = SessionFixture();
    cache = PageListCache(MemoryKeyValueStore());
    src = _WebView();
    await expectLater(cache.pages(src, '/c/9'), throwsException);
  });

  test('a marked source fails the open at once, unreported', () async {
    final s = f.make(source: src, pageLists: cache);
    await s.open().timeout(const Duration(seconds: 1));
    expect(s.phase, ReaderPhase.failed);
    expect(s.error, isNull, reason: 'icon and Retry only, no text');
    expect(src.pageCalls, ['/c/9'], reason: 'the source is not asked');
    expect(await f.diagnostics.entries(), isEmpty);
  });

  test('Retry asks the source again and opens when it works', () async {
    src.broken = false;
    final s = f.make(source: src, pageLists: cache, fresh: true);
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(s.pages, hasLength(3));
    expect(src.pageCalls.last, '/c/2');
  });

  test('a page list fetched ahead opens without asking again', () async {
    src.broken = false;
    await cache.pages(src, '/c/2', fresh: true);
    final s = f.make(source: src, pageLists: cache);
    await s.open();
    expect(s.phase, ReaderPhase.ready);
    expect(src.pageCalls.where((u) => u == '/c/2'), hasLength(1));
  });
}
