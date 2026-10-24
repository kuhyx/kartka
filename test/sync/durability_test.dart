import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/decorators/synced_progress.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';

import 'fakes.dart';

final MangaKey _key = mangaKeyOf('mangadex', '/manga/1');

/// Counts `set` calls per key, to pin the write amplification.
class _CountingKv extends MemoryKeyValueStore {
  final Map<String, int> sets = {};

  @override
  Future<void> set(String key, String value) async {
    sets[key] = (sets[key] ?? 0) + 1;
    await super.set(key, value);
  }
}

Future<void> _seedPeerProgress(InMemoryRtdb db) async {
  final peer = await engineFor('dev-z', db);
  await peer.write('progress/${mangaKeyHash(_key)}', {
    'key': _key,
    'chapterUrl': '/c/9',
    'chapterNumber': 9,
    'page': 4,
    'readAt': '2026-10-24T10:00:00.000Z',
  });
}

Future<ReadingProgress?> _replayInto(SyncEngine engine) async {
  final inner = LocalProgressRepository(MemoryKeyValueStore());
  final repo = SyncedProgressRepository(inner, Future.value(engine));
  await pumpEventQueue();
  await repo.settled;
  return await inner.watch(_key).first;
}

void main() {
  test('a change merged before the decorator existed is replayed', () async {
    final db = InMemoryRtdb();
    await _seedPeerProgress(db);
    final b = await engineFor('dev-b', db);
    await b.poll(); // nobody listening yet
    final p = await _replayInto(b);
    expect(p?.chapterNumber, 9);
    expect(b.shadow.unapplied, isEmpty);
  });

  test('a change merged but not replayed survives a restart', () async {
    final db = InMemoryRtdb();
    await _seedPeerProgress(db);
    final kv = MemoryKeyValueStore();
    final before = await engineFor('dev-b', db, kv: kv);
    await before.poll(); // then the app is killed before any replay
    final after = await engineFor('dev-b', db, kv: kv);
    expect(after.shadow.unapplied, isNotEmpty);
    expect((await _replayInto(after))?.page, 4);
  });

  test('a signed-out import costs one dirty-set write per batch', () async {
    final kv = _CountingKv();
    final engine = SyncEngine(
      shadow: await SyncShadow.load(kv),
      deviceId: 'dev-a',
      open: () async => null,
    );
    const batches = 300;
    for (var m = 0; m < batches; m++) {
      await engine.writeAll({
        for (var c = 0; c < 30; c++)
          'read/m$m/c$c': {
            'read': true,
            kHlcField: engine.tick().toStr(),
            'url': '/c/$c',
          },
      });
    }
    expect(engine.shadow.dirty, hasLength(batches * 30));
    expect(kv.sets['sync.dirty'], batches);
    // One bucket (all marks of a manga) per batch, not one entry per mark.
    expect(kv.sets.keys.where((k) => k.startsWith('sync.b.')), hasLength(300));
  });

  test('an array-coerced node is not re-pushed on every poll', () async {
    final db = InMemoryRtdb({
      'trackers': {
        'h': {
          'anilist': {
            'key': 'k',
            'service': 'anilist',
            'remoteId': '1',
            'removed': false,
            'hlc': '2026-10-24T10:00:00.000Z-0000-dev-z',
            'pushed': [null, 5],
            'lastPushedChapter': 5,
          },
        },
      },
      'revs': {'dev-z': '1'},
    });
    final b = await engineFor('dev-b', db);
    await b.poll();
    expect(b.shadow.node('trackers/h/anilist')?['pushed'], {'1': 5});
    expect(db.writes, 0, reason: 'normalised echo equals the shadow');
  });
}
