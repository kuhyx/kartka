import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';

import '../support/memory_kv.dart';

final _t0 = DateTime.utc(2026, 10, 24);
const _k = 'mangadex|/m';

extension on Any {
  Generator<ReadingProgress> get progress => combine3(
    intInRange(0, 4),
    intInRange(0, 3),
    intInRange(0, 3),
    (ch, page, at) => ReadingProgress(
      key: _k,
      chapterUrl: '/c$ch',
      chapterNumber: ch / 2,
      page: page,
      readAt: _t0.add(Duration(minutes: at)),
    ),
  );

  /// (chapter index, read?) operations on a few chapters.
  Generator<(int, bool)> get markOp =>
      combine2(intInRange(0, 3), this.bool, (c, on) => (c, on));
}

void main() {
  Glados(any.list(any.progress)).test(
    'never decreases: every emission is ahead of the previous one',
    (writes) async {
      final repo = LocalProgressRepository(MemoryKv());
      final seen = <ReadingProgress?>[];
      final sub = repo.watch(_k).listen(seen.add);
      for (final w in writes) {
        await repo.record(w);
      }
      await pumpEventQueue();
      await sub.cancel();
      for (var n = 1; n < seen.length; n++) {
        expect(seen[n]!.isAheadOf(seen[n - 1]), isTrue);
      }
    },
  );

  Glados(any.list(any.progress)).test(
    'max: the final position is an input that no input is ahead of',
    (writes) async {
      final last = await _final(writes);
      if (writes.isEmpty) return expect(last, isNull);
      expect(writes, contains(last));
      expect(writes.where((w) => w.isAheadOf(last)), isEmpty);
    },
  );

  Glados2(any.list(any.progress), any.int).test(
    'order-independent position (chapter, page)',
    (writes, seed) async {
      final a = await _final(writes);
      final b = await _final([...writes]..shuffle(Random(seed)));
      expect((b?.chapterNumber, b?.page), (a?.chapterNumber, a?.page));
    },
  );

  Glados(
    any.list(any.markOp),
  ).test('read set = chapters whose latest mark is read', (ops) async {
    var tick = 0;
    // A lagging clock: marks must still order by call sequence.
    final repo = LocalProgressRepository(
      MemoryKv(),
      now: () => _t0.add(Duration(milliseconds: -tick++)),
    );
    final expected = <String>{};
    for (final (c, on) in ops) {
      on ? await repo.markRead(_k, '/c$c') : await repo.markUnread(_k, '/c$c');
      on ? expected.add('/c$c') : expected.remove('/c$c');
    }
    expect(await repo.readChapters(_k).first, expected);
  });
}

Future<ReadingProgress?> _final(List<ReadingProgress> writes) async {
  final repo = LocalProgressRepository(MemoryKv());
  for (final w in writes) {
    await repo.record(w);
  }
  return await repo.watch(_k).first;
}
