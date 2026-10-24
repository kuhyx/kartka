import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';

import 'package:kartka/platform/memory/memory_stores.dart';

final _t0 = DateTime.utc(2026, 10, 24);
const _k = 'mangadex|/m';

ReadingProgress _p(double ch, int page, {String key = _k}) => ReadingProgress(
  key: key,
  chapterUrl: '/c$ch',
  chapterNumber: ch,
  page: page,
  readAt: _t0,
);

void main() {
  late MemoryKeyValueStore kv;
  late LocalProgressRepository repo;
  setUp(() {
    kv = MemoryKeyValueStore();
    repo = LocalProgressRepository(kv, now: () => _t0);
  });

  test('watch is null until something is recorded', () async {
    expect(await repo.watch(_k).first, isNull);
  });

  test('record keeps only forward progress', () async {
    await repo.record(_p(2, 5));
    await repo.record(_p(1, 9));
    await repo.record(_p(2, 4));
    await repo.record(_p(2, 5));
    expect(await repo.watch(_k).first, _p(2, 5));
    await repo.record(_p(2, 6));
    expect(await repo.watch(_k).first, _p(2, 6));
    expect((await kv.entries()).keys.single, 'progress/${mangaKeyHash(_k)}');
  });

  test('watch emits per key and only when that key changes', () async {
    final seen = <ReadingProgress?>[];
    final sub = repo.watch(_k).listen(seen.add);
    await pumpEventQueue();
    await repo.record(_p(1, 0, key: 'other|/x'));
    await repo.record(_p(1, 0));
    await repo.record(_p(1, 1));
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [null, _p(1, 0), _p(1, 1)]);
  });

  test('read marks: mark, unmark, per key', () async {
    await repo.markRead(_k, '/c1');
    await repo.markRead(_k, '/c2');
    await repo.markRead('other|/x', '/c9');
    await repo.markUnread(_k, '/c1');
    expect(await repo.readChapters(_k).first, {'/c2'});
    await repo.markRead(_k, '/c1');
    expect(await repo.readChapters(_k).first, {'/c1', '/c2'});
  });

  test('readMarks reports reads and unread tombstones per key', () async {
    await repo.markRead(_k, '/c1');
    await repo.markRead(_k, '/c2');
    await repo.markUnread(_k, '/c2');
    await repo.markRead('other|/x', '/c9');
    expect(await repo.readMarks(_k).first, {'/c1': true, '/c2': false});
  });

  test('markReadMany marks many chapters in one store row', () async {
    await repo.markUnread(_k, '/c0');
    await repo.markReadMany(_k, ['/c1', '/c2', '/c1']);
    await repo.markReadMany(_k, const []);
    await repo.markReadMany('other|/x', ['/c9']);
    expect(await repo.readChapters(_k).first, {'/c1', '/c2'});
    final rows = await kv.entries(prefix: 'read/');
    expect(
      rows.keys,
      unorderedEquals([
        'read/${mangaKeyHash(_k)}',
        'read/${mangaKeyHash('other|/x')}',
      ]),
    );
  });

  test('unmarking an unknown chapter writes nothing', () async {
    await repo.markUnread(_k, '/c1');
    expect(await kv.entries(), isEmpty);
  });

  test('state survives a restart over the same store', () async {
    await repo.record(_p(3, 1));
    await repo.markRead(_k, '/c1');
    final again = LocalProgressRepository(kv);
    expect(await again.watch(_k).first, _p(3, 1));
    expect(await again.readChapters(_k).first, {'/c1'});
  });
}
