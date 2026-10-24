import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_library_repository.dart';

import '../support/memory_kv.dart';

final _t0 = DateTime.utc(2026, 10, 24);

extension on Any {
  // Few keys, few timestamps: collisions and equal-stamp ties are common.
  Generator<LibraryEntry> get entry => combine4(
    choose(['/a', '/b', '/c']),
    intInRange(0, 3),
    choose(['x', 'y']),
    this.bool,
    (url, at, title, removed) => LibraryEntry(
      key: mangaKeyOf('mangadex', url),
      sourceId: 'mangadex',
      mangaUrl: url,
      title: title,
      addedAt: _t0,
      updatedAt: _t0.add(Duration(seconds: at)),
      removed: removed,
    ),
  );
}

Future<Set<LibraryEntry>> _replay(Iterable<LibraryEntry> writes) async {
  final kv = MemoryKv();
  final repo = LocalLibraryRepository(kv);
  for (final w in writes) {
    await repo.upsert(w);
  }
  // Read back through a fresh instance: the persisted state is what counts.
  return (await LocalLibraryRepository(kv).watch().first).toSet();
}

void main() {
  Glados2(any.list(any.entry), any.int).test(
    'converges: any delivery order gives the same library',
    (writes, seed) async {
      final shuffled = [...writes]..shuffle(Random(seed));
      expect(await _replay(shuffled), await _replay(writes));
    },
  );

  Glados(any.list(any.entry)).test(
    'idempotent: delivering every write twice changes nothing',
    (writes) async {
      expect(await _replay([...writes, ...writes]), await _replay(writes));
    },
  );

  Glados(any.list(any.entry)).test(
    "newest wins: each visible entry carries its key's latest updatedAt",
    (writes) async {
      for (final e in await _replay(writes)) {
        final latest = writes
            .where((w) => w.key == e.key)
            .map((w) => w.updatedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        expect(e.updatedAt, latest);
        expect(e.removed, isFalse);
      }
    },
  );
}
