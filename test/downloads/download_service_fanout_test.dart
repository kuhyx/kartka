import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_index.dart';

import 'service_harness.dart';

const _n = 775;

void main() {
  test('download progress ticks wake only the manga they belong to', () async {
    final h = Harness();
    // 775 other library manga, each with one chapter stored offline.
    final index = DownloadIndex();
    for (var i = 0; i < _n; i++) {
      index.put(
        'mangadex|/other/$i',
        OfflineChapter(
          chapter: const ChapterInfo(url: '/c', name: 'c'),
          pageCount: 1,
          bytes: 1,
          downloadedAt: DateTime.utc(2026),
        ),
      );
    }
    await h.kv.set(indexKvKey, index.encode());
    final s = h.service();
    await s.start();

    final badges = <String, bool>{};
    final subs = [
      for (var i = 0; i < _n; i++)
        s.hasDownloads('mangadex|/other/$i').listen((d) => badges['$i'] = d),
      s.hasDownloads(mangaKey).listen((d) => badges['active'] = d),
    ];
    await pumpEventQueue();
    expect(badges, hasLength(_n + 1));
    final before = s.watcherReads;

    await s.enqueue(mangaKey, ch1);
    await waitFor(s, ch1, DownloadStatus.done);
    await pumpEventQueue();

    // Before: every tick and every queue change re-read all 776 badges
    // (thousands of reads for one 3-page chapter).
    expect(s.watcherReads - before, lessThan(20));
    expect(badges['active'], isTrue, reason: 'the finished chapter shows');
    expect(badges.values.where((d) => d), hasLength(_n + 1));
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('pause and resume still reach every watcher', () async {
    final h = Harness();
    final s = h.service();
    await s.start();
    final queue = <bool>[];
    final sub = s.watchAll().listen((snap) => queue.add(snap.paused));
    await pumpEventQueue();
    await s.pause();
    await s.resume();
    expect(queue, [false, true, false]);
    await sub.cancel();
  });
}
