import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_category_repository.dart';

import 'package:kartka/platform/memory/memory_stores.dart';

final _t0 = DateTime.utc(2026, 10, 24);

Category _cat(String id, {int order = 0, int at = 0, bool removed = false}) =>
    Category(
      id: id,
      name: 'n$id',
      order: order,
      updatedAt: _t0.add(Duration(seconds: at)),
      removed: removed,
    );

void main() {
  late MemoryKeyValueStore kv;
  late LocalCategoryRepository repo;
  var clock = _t0;
  setUp(() {
    kv = MemoryKeyValueStore();
    clock = _t0;
    repo = LocalCategoryRepository(kv, now: () => clock);
  });

  test('watch lists live categories by order, then id', () async {
    await repo.upsert(_cat('b', order: 1));
    await repo.upsert(_cat('a', order: 1));
    await repo.upsert(_cat('z'));
    await repo.upsert(_cat('gone', removed: true));
    expect([for (final c in await repo.watch().first) c.id], ['z', 'a', 'b']);
  });

  test('category ids with slashes are stored under a hashed key', () async {
    await repo.upsert(_cat('Reading/Now'));
    expect(
      (await kv.entries()).keys.single,
      'categories/${mangaKeyHash('Reading/Now')}',
    );
  });

  test('upsert is last-writer-wins on updatedAt', () async {
    await repo.upsert(_cat('a', order: 5, at: 2));
    await repo.upsert(_cat('a', order: 1, at: 1));
    expect((await repo.watch().first).single.order, 5);
  });

  test('membership: set, unset, and only true values are reported', () async {
    await repo.setMembership('s|/m', 'a', true);
    await repo.setMembership('s|/m', 'b', true);
    await repo.setMembership('s|/n', 'a', true);
    clock = _t0.add(const Duration(seconds: 1));
    await repo.setMembership('s|/m', 'b', false);
    await repo.setMembership('s|/n', 'a', false);
    expect(await repo.watchMembership().first, {
      's|/m': {'a'},
    });
  });

  test('membership re-set at a lagging clock still lands', () async {
    await repo.setMembership('s|/m', 'a', true);
    await repo.setMembership('s|/m', 'a', false);
    await repo.setMembership('s|/m', 'a', true);
    expect(await repo.watchMembership().first, {
      's|/m': {'a'},
    });
  });

  test('redundant membership writes touch nothing', () async {
    await repo.setMembership('s|/m', 'a', false);
    expect(await kv.entries(), isEmpty);
    await repo.setMembership('s|/m', 'a', true);
    final before = await kv.entries();
    await repo.setMembership('s|/m', 'a', true);
    expect(await kv.entries(), before);
  });

  test('state survives a restart over the same store', () async {
    await repo.upsert(_cat('a'));
    await repo.setMembership('s|/m', 'a', true);
    final again = LocalCategoryRepository(kv);
    expect(await again.watch().first, [_cat('a')]);
    expect(await again.watchMembership().first, {
      's|/m': {'a'},
    });
  });
}
