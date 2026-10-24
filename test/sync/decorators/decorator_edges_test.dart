import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_category_repository.dart';
import 'package:kartka/library/data/local_library_repository.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/decorators/sync_repository_decorator.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';

import '../device_harness.dart';

final MangaKey _key = mangaKeyOf('mangadex', '/manga/1');

ReadingProgress _at(String chapter, int page) => ReadingProgress(
  key: _key,
  chapterUrl: chapter,
  chapterNumber: chapter == '/c/1' ? 1 : 2,
  page: page,
  readAt: DateTime.utc(2026, 10, 24),
);

void main() {
  test('markReadMany is one PATCH and one revision per manga', () async {
    final db = InMemoryRtdb();
    final a = await Device.create('dev-a', db);
    final b = await Device.create('dev-b', db);
    await a.progress.markReadMany(_key, [for (var i = 0; i < 40; i++) '/c/$i']);
    expect(db.writes, 1);
    expect(db.tree['revs'], {'dev-a': '1'});
    await a.progress.markReadMany(_key, const []);
    expect(db.writes, 1);
    await b.poll();
    expect(await b.progress.readMarks(_key).first, hasLength(40));
    await a.dispose();
    await b.dispose();
  });

  test('page turns in one chapter defer; a chapter change pushes', () async {
    final db = InMemoryRtdb();
    final a = await Device.create('dev-a', db);
    await a.progress.record(_at('/c/1', 0));
    expect(db.writes, 1, reason: 'first record pushes at once');
    await a.progress.record(_at('/c/1', 1));
    await a.progress.record(_at('/c/1', 2));
    expect(db.writes, 1, reason: 'page turns wait for the deferral window');
    await a.progress.record(_at('/c/2', 0));
    expect(db.writes, 3, reason: 'flush of the held page, then the chapter');
    final remote = (db.tree['progress']! as Map)[mangaKeyHash(_key)] as Map;
    expect(remote['chapterUrl'], '/c/2');
    await a.engine.dispose();
    await a.dispose();
  });

  test('if the engine never starts, local writes still work', () async {
    final kv = MemoryKeyValueStore();
    final decorator = SyncRepositoryDecorator(
      () => Future<SyncEngine>.error(StateError('no prefs plugin')),
    );
    final library = decorator.library(LocalLibraryRepository(kv));
    final categories = decorator.categories(LocalCategoryRepository(kv));
    final progress = decorator.progress(LocalProgressRepository(kv));
    final entry = LibraryEntry(
      key: _key,
      sourceId: 'mangadex',
      mangaUrl: '/manga/1',
      title: 'One',
      addedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await library.upsert(entry);
    expect((await library.watch().first).single.title, 'One');
    await library.remove(_key);
    expect(await library.watch().first, isEmpty);
    final cat = Category(
      id: 'c',
      name: 'C',
      order: 0,
      updatedAt: DateTime.utc(2026),
    );
    await categories.upsert(cat);
    await categories.setMembership(_key, 'c', true);
    expect(await categories.watchMembership().first, {
      _key: {'c'},
    });
    await progress.record(_at('/c/1', 3));
    await progress.markRead(_key, '/c/1');
    await progress.markReadMany(_key, ['/c/2']);
    expect((await progress.watch(_key).first)!.page, 3);
    expect(await progress.readChapters(_key).first, contains('/c/2'));
  });
}
