import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/wire/wire.dart';

import '../device_harness.dart';

const _n = 775;

MangaKey _key(int i) => mangaKeyOf('mangadex', '/manga/$i');

LibraryEntry _entry(int i) => LibraryEntry(
  key: _key(i),
  sourceId: 'mangadex',
  mangaUrl: '/manga/$i',
  title: 'Title $i',
  coverUrl: 'https://c/$i.jpg',
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ReadingProgress _progress(int i) => ReadingProgress(
  key: _key(i),
  chapterUrl: '/chapter/1',
  chapterNumber: 1,
  page: 3,
  readAt: DateTime.utc(2026, 10, 24),
);

void main() {
  test('a full pull of $_n entries costs O(N) library emissions', () async {
    final db = InMemoryRtdb();
    final a = await Device.create('dev-a', db);
    final b = await Device.create('dev-b', db);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });
    // One push of everything: the library, a progress row and three read
    // marks per manga, as a long-lived second device would have it.
    final hlc = a.engine.tick().toStr();
    await a.engine.writeAll({
      for (var i = 0; i < _n; i++) ...{
        libraryPath(_key(i)): stampChanges(
          null,
          libraryValues(_entry(i)),
          hlc,
        )!,
        progressPath(_key(i)): rtdbNormal(_progress(i).toJson()),
        for (var c = 0; c < 3; c++)
          readPath(_key(i), '/chapter/$c'): {
            'read': true,
            kHlcField: hlc,
            'url': '/chapter/$c',
            'key': _key(i),
          },
      },
    });

    var emissions = 0;
    var delivered = 0;
    final lib = b.library.watch().listen((l) {
      emissions++;
      delivered += l.length;
    });
    final seen = <int>{};
    final watchers = [
      for (var i = 0; i < _n; i++)
        b.progress.watch(_key(i)).listen((p) {
          if (p != null) seen.add(i);
        }),
    ];
    await pumpEventQueue();
    emissions = 0;
    delivered = 0;

    await b.poll();

    final onB = await b.library.watch().first;
    expect(onB, hasLength(_n));
    expect(seen, hasLength(_n), reason: 'every progress row arrived');
    // Before: one emission per replayed row (~775, ~300k list items).
    expect(emissions, lessThanOrEqualTo(3));
    expect(delivered, lessThanOrEqualTo(3 * _n));
    await lib.cancel();
    for (final w in watchers) {
      await w.cancel();
    }
  }, timeout: const Timeout(Duration(seconds: 50)));
}
