import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migrator.dart';
import 'package:kartka/tracking/common/track_binding.dart';

import 'fakes.dart';

const _to = MangaSummary(
  sourceId: 'suwayomi:2327480808438768017',
  url: '/atsu/one',
  title: 'One Piece',
  coverUrl: 'https://atsu.test/c.jpg',
);
final MangaKey _newKey = mangaKeyOf(_to.sourceId, _to.url);

void main() {
  late World w;
  late LibraryEntry old;

  setUp(() async {
    w = World()..install();
    old = await w.add('One Piece');
    w.numbers.lists[old.key] = chaptersOf('/old', [1, 2, 3, 4, 5, 6, 7]);
  });

  tearDown(() => w.tracking.dispose());

  Future<void> migrate() =>
      migrateEntry(w.deps, from: old, target: w.target, to: _to);

  test('progress moves by chapter number with its page', () async {
    w.target.chapterLists[_to.url] = chaptersOf('/new', [1, 2, 3, 4, 5]);
    await w.repos.progress.record(
      ReadingProgress(
        key: old.key,
        chapterUrl: '/old/3',
        chapterNumber: 3,
        page: 4,
        readAt: DateTime.utc(2026),
      ),
    );
    await migrate();
    final p = await w.repos.progress.watch(_newKey).first;
    expect(p?.chapterUrl, '/new/3');
    expect(p?.chapterNumber, 3);
    expect(p?.page, 4);
    expect(p?.readAt, DateTime.utc(2026));
  });

  test('a chapter missing on the target: nearest lower one, marks by '
      'number, missing marks skipped', () async {
    w.target.chapterLists[_to.url] = chaptersOf('/new', [1, 2, 3, 4, 6]);
    final repo = w.repos.progress;
    await repo.record(
      ReadingProgress(
        key: old.key,
        chapterUrl: '/old/5',
        chapterNumber: 5,
        page: 3,
        readAt: DateTime.utc(2026),
      ),
    );
    await repo.markRead(old.key, '/old/6');
    await repo.markRead(old.key, '/old/7'); // Not on the target.
    await repo.markRead(old.key, '/old/2');
    await repo.markUnread(old.key, '/old/2'); // An unread tombstone.
    await repo.markRead(old.key, '/old/unknown'); // No number known.
    await migrate();
    final p = await repo.watch(_newKey).first;
    expect(p?.chapterUrl, '/new/4');
    expect(p?.chapterNumber, 4);
    expect(p?.page, 0);
    expect(await repo.readMarks(_newKey).first, {
      '/new/6': true,
      '/new/2': false,
    });
  });

  test('no progress and no target chapter below it records none', () async {
    w.target.chapterLists[_to.url] = chaptersOf('/new', [2]);
    await w.repos.progress.record(
      ReadingProgress(
        key: old.key,
        chapterUrl: '/old/1',
        chapterNumber: 1,
        page: 0,
        readAt: DateTime.utc(2026),
      ),
    );
    await migrate();
    expect(await w.repos.progress.watch(_newKey).first, isNull);
  });

  test('categories move to the new entry', () async {
    final cats = w.repos.categories;
    await cats.setMembership(old.key, 'a', true);
    await cats.setMembership(old.key, 'b', true);
    await migrate();
    final m = await cats.watchMembership().first;
    expect(m[_newKey], {'a', 'b'});
    expect(m[old.key] ?? const <String>{}, isEmpty);
  });

  test('trackers move with their pushed count', () async {
    await w.bindings.put(
      TrackBinding(
        key: old.key,
        service: 'anilist',
        remoteId: '42',
        lastPushedChapter: 3,
      ),
    );
    await migrate();
    expect(await w.bindings.all(), [
      TrackBinding(
        key: _newKey,
        service: 'anilist',
        remoteId: '42',
        lastPushedChapter: 3,
      ),
    ]);
  });

  test('the old entry is replaced, keeping when it was added', () async {
    await migrate();
    final entries = await w.entries();
    expect(entries.keys, [_newKey]);
    final e = entries[_newKey]!;
    expect(e.sourceId, _to.sourceId);
    expect(e.mangaUrl, _to.url);
    expect(e.title, 'One Piece');
    expect(e.coverUrl, _to.coverUrl);
    expect(e.addedAt, old.addedAt);
  });

  test('works without tracking or a chapter-number lookup', () async {
    await w.repos.progress.markRead(old.key, '/old/1');
    final bare = MigrationDeps(
      library: w.repos.library,
      categories: w.repos.categories,
      progress: w.repos.progress,
      findTarget: () async => null,
      backups: w.backups,
    );
    await migrateEntry(bare, from: old, target: w.target, to: _to);
    expect((await w.entries()).keys, [_newKey]);
    expect(await w.repos.progress.readMarks(_newKey).first, isEmpty);
  });
}
