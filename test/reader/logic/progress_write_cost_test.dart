// What a page turn costs on Android storage: the debounced progress write
// must rewrite only the shard holding `progress/<hash>`, never the store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/kv_shard_files.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kartka_progress'));
  tearDown(() => dir.deleteSync(recursive: true));

  Set<String> shardFiles() => {
    for (final e in dir.listSync())
      if (e.path.endsWith('.json')) e.uri.pathSegments.last,
  };

  test('a settled page rewrites one shard; re-reads write nothing', () async {
    final kv = FileKeyValueStore(dir, window: const Duration(hours: 1));
    // A big existing library: every shard holds data.
    for (var i = 0; i < 2000; i++) {
      await kv.set('library/$i', '{"title":"manga $i"}');
    }
    await kv.flush();
    expect(shardFiles(), hasLength(kvShardCount));
    for (final f in dir.listSync()) {
      f.deleteSync();
    }

    final key = mangaKeyOf('mangadex', '/m/1');
    final repo = LocalProgressRepository(kv);
    Future<void> record(int page) => repo.record(
      ReadingProgress(
        key: key,
        chapterUrl: '/c/1',
        chapterNumber: 1,
        page: page,
        readAt: DateTime.utc(2026, 10, 29, 12, 0, page),
      ),
    );
    final recorder = ProgressRecorder(
      pageCount: 20,
      record: record,
      markRead: () async {},
      debounce: Duration.zero,
    );
    for (var p = 0; p < 6; p++) {
      recorder.onPage(p);
    }
    await recorder.flush();
    await kv.flush();
    expect(shardFiles(), {
      kvShardFileName(kvShardOf('progress/${mangaKeyHash(key)}')),
    });

    for (final f in dir.listSync()) {
      f.deleteSync();
    }
    await record(5); // Same page again: not ahead, so no store write.
    await kv.flush();
    expect(shardFiles(), isEmpty);
    recorder.dispose();
  });
}
