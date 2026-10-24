import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_category_repository.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

final _t0 = DateTime.utc(2026, 10, 24);

extension on Any {
  // Few ids and stamps, so overwrites and equal-stamp ties are common.
  Generator<Category> get category => combine4(
    choose(['a', 'b']),
    intInRange(0, 3),
    intInRange(0, 3),
    this.bool,
    (id, order, at, removed) => Category(
      id: id,
      name: 'n$order',
      order: order,
      updatedAt: _t0.add(Duration(seconds: at)),
      removed: removed,
    ),
  );
}

Future<Set<Category>> _replay(Iterable<Category> writes) async {
  final kv = MemoryKeyValueStore();
  final repo = LocalCategoryRepository(kv);
  for (final w in writes) {
    await repo.upsert(w);
  }
  return (await LocalCategoryRepository(kv).watch().first).toSet();
}

void main() {
  Glados2(any.list(any.category), any.int).test(
    'converges: any delivery order gives the same categories',
    (writes, seed) async {
      final shuffled = [...writes]..shuffle(Random(seed));
      expect(await _replay(shuffled), await _replay(writes));
    },
  );

  Glados(any.list(any.category)).test(
    'idempotent: delivering every write twice changes nothing',
    (writes) async {
      expect(await _replay([...writes, ...writes]), await _replay(writes));
    },
  );
}
