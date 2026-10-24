import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/wire/wire.dart';

import '../device_harness.dart';

final _key = mangaKeyOf('mangadex', '/manga/1');

LibraryEntry _entry(String title, {bool removed = false}) => LibraryEntry(
  key: _key,
  sourceId: 'mangadex',
  mangaUrl: '/manga/1',
  title: title,
  coverUrl: 'https://c/1.jpg',
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  removed: removed,
);

ReadingProgress _at(double chapter, int page) => ReadingProgress(
  key: _key,
  chapterUrl: '/chapter/$chapter',
  chapterNumber: chapter,
  page: page,
  readAt: DateTime.utc(2026, 10, 24),
);

void main() {
  late InMemoryRtdb db;
  late Device a;
  late Device b;

  setUp(() async {
    db = InMemoryRtdb();
    a = await Device.create('dev-a', db);
    b = await Device.create('dev-b', db);
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('an entry added on one device appears on the other', () async {
    await a.library.upsert(_entry('One Piece'));
    await b.poll();
    final onB = await b.library.watch().first;
    expect(onB.single.title, 'One Piece');
    expect(onB.single.coverUrl, 'https://c/1.jpg');
  });

  test('a rename and a concurrent removal both survive', () async {
    await a.library.upsert(_entry('Old'));
    await b.poll();
    await a.library.upsert(_entry('New'));
    await b.library.remove(_key);
    await a.poll();
    await b.poll();
    for (final d in [a, b]) {
      expect(await d.library.watch().first, isEmpty);
      final node = d.engine.shadow.node(libraryPath(_key))!;
      expect(node['title'], 'New');
      expect(node['removed'], isTrue);
    }
  });

  test('re-adding after a removal reaches the other device', () async {
    await a.library.upsert(_entry('One'));
    await a.library.remove(_key);
    await b.poll();
    expect(await b.library.watch().first, isEmpty);
    await b.library.upsert(_entry('One'));
    await a.poll();
    expect((await a.library.watch().first).single.title, 'One');
  });

  test('an unchanged upsert writes nothing remote', () async {
    await a.library.upsert(_entry('One'));
    final writes = db.writes;
    await a.library.upsert(_entry('One'));
    expect(db.writes, writes);
  });

  test('categories and membership sync, including un-membering', () async {
    final cat = Category(
      id: 'Reading/now.v2',
      name: 'Reading',
      order: 1,
      updatedAt: DateTime.utc(2026),
    );
    await a.categories.upsert(cat);
    await a.categories.setMembership(_key, cat.id, true);
    await b.poll();
    expect((await b.categories.watch().first).single.id, cat.id);
    expect(await b.categories.watchMembership().first, {
      _key: {cat.id},
    });
    await a.categories.setMembership(_key, cat.id, false);
    await b.poll();
    expect(await b.categories.watchMembership().first, isEmpty);
  });

  test('progress converges on the furthest and never decreases', () async {
    await a.progress.record(_at(5, 2));
    await b.progress.record(_at(3, 9));
    await a.poll();
    await b.poll();
    for (final d in [a, b]) {
      expect((await d.progress.watch(_key).first)!.chapterNumber, 5);
    }
    await b.progress.record(_at(4, 0));
    await a.poll();
    expect((await a.progress.watch(_key).first)!.chapterNumber, 5);
    expect(
      (db.tree['progress']! as Map)[mangaKeyHash(_key)],
      containsPair('chapterNumber', 5),
    );
  });

  test('read marks and unread tombstones reach the other device', () async {
    await a.progress.markRead(_key, '/chapter/1');
    await b.poll();
    expect(await b.progress.readMarks(_key).first, {'/chapter/1': true});
    await a.progress.markUnread(_key, '/chapter/1');
    await b.poll();
    expect(await b.progress.readMarks(_key).first, {'/chapter/1': false});
  });

  test('a read node without key falls back to the library node', () async {
    await a.library.upsert(_entry('One'));
    final hash = mangaKeyHash(_key);
    await db.patch({
      'read/$hash/x': {
        'read': true,
        'hlc': '2030-01-01T00:00:00.000Z-0000-dev-z',
        'url': '/chapter/9',
      },
      'revs/dev-z': '1',
    });
    await b.poll();
    expect(await b.progress.readMarks(_key).first, {'/chapter/9': true});
  });

  test('malformed remote nodes are skipped, not fatal', () async {
    await db.patch({
      'library/bad': {'title': 'no key'},
      'categories/bad': {'name': 'no order'},
      'membership/h/c': {'member': 'yes'},
      'progress/bad': {'chapterNumber': 'x'},
      'read/h/c': {'read': true},
      'revs/dev-z': '1',
    });
    await b.poll();
    expect(await b.library.watch().first, isEmpty);
    expect(await b.categories.watch().first, isEmpty);
    expect(await b.categories.watchMembership().first, isEmpty);
  });
}
