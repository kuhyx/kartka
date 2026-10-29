import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/updates/state/update_scheduler.dart';

/// A checker whose checks finish only when the test completes them, and
/// which records how many run at once, overall and per source.
class GatedChecker {
  final Map<MangaKey, Completer<UpdateResult>> pending = {};
  final Map<String, int> _perSource = {};
  int active = 0;
  int maxActive = 0;
  int maxPerSource = 0;

  Future<UpdateResult> check(MangaKey key) async {
    final source = splitMangaKey(key).$1;
    active++;
    final n = _perSource[source] = (_perSource[source] ?? 0) + 1;
    if (active > maxActive) maxActive = active;
    if (n > maxPerSource) maxPerSource = n;
    final done = pending[key] = Completer<UpdateResult>();
    try {
      return await done.future;
    } finally {
      active--;
      _perSource[source] = _perSource[source]! - 1;
    }
  }

  /// Completes every check in flight.
  Future<void> releaseAll() async {
    for (final e in [...pending.entries]) {
      pending.remove(e.key);
      e.value.complete(
        UpdateFound(
          e.key,
          chapters: const [],
          added: const [],
          firstCheck: false,
        ),
      );
    }
    await pumpEventQueue();
  }
}

void main() {
  test('runs at most 4 at once and 1 per source', () async {
    final keys = [
      for (final s in ['a', 'b', 'c', 'd', 'e', 'f'])
        for (var i = 0; i < 3; i++) mangaKeyOf(s, '/m/$i'),
    ];
    final checker = GatedChecker();
    final done = <int>[];
    final run = checkAll(
      keys,
      checker.check,
      onResult: (_, count) => done.add(count),
    );
    await pumpEventQueue();
    expect(checker.active, 4);
    // The head of the queue is all source `a`: a busy source must not stall
    // the others, so the first four are one per source.
    expect(
      {for (final k in checker.pending.keys) splitMangaKey(k).$1},
      {'a', 'b', 'c', 'd'},
    );
    while (checker.pending.isNotEmpty) {
      await checker.releaseAll();
    }
    final results = await run;
    expect(results, hasLength(keys.length));
    expect(checker.maxActive, 4);
    expect(checker.maxPerSource, 1);
    expect(done, [for (var i = 1; i <= keys.length; i++) i]);
  });

  test('one source: strictly one at a time', () async {
    final keys = [for (var i = 0; i < 3; i++) mangaKeyOf('a', '/m/$i')];
    final checker = GatedChecker();
    final run = checkAll(keys, checker.check);
    await pumpEventQueue();
    expect(checker.active, 1);
    while (checker.pending.isNotEmpty) {
      await checker.releaseAll();
    }
    expect(await run, hasLength(3));
    expect(checker.maxActive, 1);
  });

  test('every suwayomi: source shares one server: at most 2 at once', () async {
    final keys = [
      for (final s in ['suwayomi:1', 'suwayomi:2', 'suwayomi:3', 'mangadex'])
        mangaKeyOf(s, '/m'),
    ];
    final checker = GatedChecker();
    final run = checkAll(keys, checker.check);
    await pumpEventQueue();
    expect(
      [for (final k in checker.pending.keys) splitMangaKey(k).$1],
      ['suwayomi:1', 'suwayomi:2', 'mangadex'],
    );
    while (checker.pending.isNotEmpty) {
      await checker.releaseAll();
    }
    expect(await run, hasLength(4));
    expect(updateHostOf('suwayomi:42'), 'suwayomi');
    expect(updateHostOf('mangadex'), 'mangadex');
  });

  test('no keys completes at once with nothing', () async {
    expect(await checkAll(const [], (_) => throw StateError('no')), isEmpty);
  });

  test('a check that throws becomes UpdateFailed, the run goes on', () async {
    final keys = [mangaKeyOf('a', '/1'), mangaKeyOf('a', '/2')];
    final results = await checkAll(keys, (key) async {
      if (key.endsWith('/1')) throw StateError('boom');
      return UpdateFound(
        key,
        chapters: const [],
        added: const [],
        firstCheck: true,
      );
    });
    expect(results.whereType<UpdateFailed>().single.key, keys.first);
    expect(results.whereType<UpdateFound>().single.key, keys.last);
  });
}
