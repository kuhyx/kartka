import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/migration_backup.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/tracking/common/track_binding.dart';

import 'fakes.dart';

void main() {
  test(
    'the backup holds every part of the library a migration moves',
    () async {
      final w = World();
      final e = await w.add('One Piece');
      await w.repos.categories.upsert(
        Category(
          id: 'a',
          name: 'Reading',
          order: 0,
          updatedAt: DateTime.utc(2025),
        ),
      );
      await w.repos.categories.setMembership(e.key, 'a', true);
      await w.repos.progress.record(
        ReadingProgress(
          key: e.key,
          chapterUrl: '/old/3',
          chapterNumber: 3,
          page: 1,
          readAt: DateTime.utc(2026),
        ),
      );
      await w.repos.progress.markRead(e.key, '/old/9');
      await w.bindings.put(
        TrackBinding(key: e.key, service: 'anilist', remoteId: '42'),
      );
      final key = await exportBackup(w.deps);
      expect(key, 'backups/kartka-backup-20261025T123005Z.json');
      final json = jsonDecode(
        utf8.decode((await w.backups.get(key))!),
      ) as Map<String, Object?>;
      expect(json['format'], 'kartka-backup');
      expect(json['version'], 1);
      expect(json['createdAt'], '2026-10-25T12:30:05.000Z');
      expect((json['library']! as List<Object?>).single, e.toJson());
      expect(
        (json['categories']! as List<Object?>).single,
        containsPair('id', 'a'),
      );
      expect(json['membership'], {
        e.key: ['a'],
      });
      expect(
        (json['progress']! as Map<String, Object?>)[e.key],
        containsPair('chapterNumber', 3.0),
      );
      expect(json['readMarks'], {
        e.key: {'/old/9': true},
      });
      expect(json['trackers'], [
        {'key': e.key, 'service': 'anilist', 'remoteId': '42'},
      ]);
      await w.tracking.dispose();
    },
  );

  test('without tracking the backup has no trackers', () async {
    final w = World();
    final bare = MigrationDeps(
      library: w.repos.library,
      categories: w.repos.categories,
      progress: w.repos.progress,
      findTarget: () async => null,
      backups: w.backups,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    final key = await exportBackup(bare);
    final json = jsonDecode(
      utf8.decode((await w.backups.get(key))!),
    ) as Map<String, Object?>;
    expect(json['trackers'], isEmpty);
    expect(json['library'], isEmpty);
  });
}
