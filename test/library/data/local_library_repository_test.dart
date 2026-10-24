import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_library_repository.dart';

import '../support/memory_kv.dart';

final _t0 = DateTime.utc(2026, 10, 24);

LibraryEntry _entry(
  String url, {
  int at = 0,
  String? title,
  bool removed = false,
}) => LibraryEntry(
  key: mangaKeyOf('mangadex', url),
  sourceId: 'mangadex',
  mangaUrl: url,
  title: title ?? url,
  addedAt: _t0,
  updatedAt: _t0.add(Duration(seconds: at)),
  removed: removed,
);

void main() {
  late MemoryKv kv;
  late LocalLibraryRepository repo;
  setUp(() {
    kv = MemoryKv();
    repo = LocalLibraryRepository(
      kv,
      now: () => _t0.add(const Duration(seconds: 5)),
    );
  });

  test('upsert stores under library/<hash> and watch emits it', () async {
    await repo.upsert(_entry('/a'));
    expect(kv.data.keys, ['library/${mangaKeyHash('mangadex|/a')}']);
    expect(await repo.watch().first, [_entry('/a')]);
  });

  test('older update loses, newer wins', () async {
    await repo.upsert(_entry('/a', at: 2, title: 'new'));
    await repo.upsert(_entry('/a', at: 1, title: 'old'));
    expect((await repo.watch().first).single.title, 'new');
    await repo.upsert(_entry('/a', at: 3, title: 'newest'));
    expect((await repo.watch().first).single.title, 'newest');
  });

  test('remove tombstones and hides the entry; re-add after it wins', () async {
    await repo.upsert(_entry('/a'));
    await repo.remove(mangaKeyOf('mangadex', '/a'));
    expect(await repo.watch().first, isEmpty);
    expect(kv.data, hasLength(1));
    await repo.upsert(_entry('/a', at: 9));
    expect(await repo.watch().first, [_entry('/a', at: 9)]);
  });

  test('remove steps past a future updatedAt (clock skew)', () async {
    await repo.upsert(_entry('/a', at: 60));
    await repo.remove(mangaKeyOf('mangadex', '/a'));
    expect(await repo.watch().first, isEmpty);
  });

  test('remove of an unknown or removed key writes nothing', () async {
    await repo.remove('mangadex|/nope');
    expect(kv.data, isEmpty);
    await repo.upsert(_entry('/a', removed: true));
    final before = Map.of(kv.data);
    await repo.remove(mangaKeyOf('mangadex', '/a'));
    expect(kv.data, before);
  });

  test('state survives a restart over the same store', () async {
    await repo.upsert(_entry('/a'));
    await repo.upsert(_entry('/b'));
    expect(await LocalLibraryRepository(kv).watch().first, hasLength(2));
  });
}
