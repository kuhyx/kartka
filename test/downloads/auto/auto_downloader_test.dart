import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/auto/auto_downloader.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import '../fakes.dart';

LibraryEntry _entry(String url, {bool removed = false}) => LibraryEntry(
  key: mangaKeyOf('mangadex', url),
  sourceId: 'mangadex',
  mangaUrl: url,
  title: url,
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  removed: removed,
);

ChapterInfo _ch(String url) => ChapterInfo(url: url, name: url);

void main() {
  late MemoryKeyValueStore kv;
  late FakeSource source;
  late List<(String, String)> queued;
  late List<LibraryEntry> library;

  AutoDownloader auto() => AutoDownloader(
    kv: kv,
    library: () => Stream.value(library),
    findSource: (id) async => id == 'mangadex' ? source : null,
    enqueue: (key, c) async => queued.add((key, c.url)),
  );

  setUp(() {
    kv = MemoryKeyValueStore();
    source = FakeSource(chapterList: [_ch('/c1')]);
    queued = [];
    library = [_entry('/m1')];
  });

  test('disabled by default: check does nothing', () async {
    final a = auto();
    expect(await a.enabled(), isFalse);
    expect(await a.check(), 0);
    expect(source.chapterCalls, 0);
  });

  test('first sight is a baseline; later new chapters are queued', () async {
    final a = auto();
    await a.setEnabled(enabled: true);
    expect(await a.enabled(), isTrue);
    expect(await a.check(), 0);
    expect(queued, isEmpty);
    source.chapterList = [_ch('/c1'), _ch('/c2'), _ch('/c3')];
    expect(await a.check(), 2);
    expect(queued.map((q) => q.$2), ['/c2', '/c3']);
    expect(await a.check(), 0);
  });

  test('skips removed entries, missing sources and failing sources', () async {
    library = [
      _entry('/gone', removed: true),
      LibraryEntry(
        key: mangaKeyOf('nosuch', '/x'),
        sourceId: 'nosuch',
        mangaUrl: '/x',
        title: 'x',
        addedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      _entry('/m1'),
    ];
    final a = auto();
    await a.setEnabled(enabled: true);
    source.failChapters = true;
    expect(await a.check(), 0);
    expect(source.chapterCalls, 1);
  });

  test('checkIfDue runs at most once per period', () async {
    var now = DateTime.utc(2026, 10, 24, 8);
    final a = AutoDownloader(
      kv: kv,
      library: () => Stream.value(library),
      findSource: (id) async => source,
      enqueue: (key, c) async {},
      now: () => now,
    );
    await a.setEnabled(enabled: true);
    expect(await a.checkIfDue(), isTrue);
    expect(await a.checkIfDue(), isFalse);
    now = now.add(const Duration(hours: 6));
    expect(await a.checkIfDue(), isTrue);
    expect(source.chapterCalls, 2);
  });
}
