import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_index.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

import 'fakes.dart';
import 'service_harness.dart';

void main() {
  test('enqueue downloads every page and serves kartka-blob pages', () async {
    final h = Harness();
    final s = h.service();
    expect(await s.watch(mangaKey, ch1.url).first, DownloadState.none);
    expect(await s.offlinePages(mangaKey, ch1.url), isNull);
    await s.enqueue(mangaKey, ch1);
    final done = await waitFor(s, ch1, DownloadStatus.done);
    expect(done.pagesDone, 3);
    final pages = (await s.offlinePages(mangaKey, ch1.url))!;
    expect(pages.map((p) => p.index), [0, 1, 2]);
    expect(pages.first.imageUrl, startsWith('kartka-blob://downloads/'));
    expect(pages.first.headers, isEmpty);
    final loader = PageImageLoader(http: FakeKartkaHttp(), blobs: h.blobs);
    expect(
      await loader.load(pages.last),
      fakeImage(fixturePages().last.imageUrl),
    );
    expect(await s.hasDownloads(mangaKey).first, isTrue);
    expect((await s.watchAll().first).queue, isEmpty);
  });

  test('downloadedChapters: completed only, newest first, full info', () async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(maxChapters: 1);
    final ch3 = ChapterInfo(
      url: '/chapter/3',
      name: 'Ch. 3',
      number: 3,
      uploadedAt: DateTime.utc(2026, 10),
      scanlator: 'Team X',
    );
    const extra = ChapterInfo(url: '/extra', name: 'Extra');
    expect(await s.downloadedChapters(mangaKey), isEmpty);
    for (final c in [ch1, ch3, extra, ch2]) {
      await s.enqueue(mangaKey, c);
    }
    h.loader.gate!.complete();
    await waitFor(s, ch2, DownloadStatus.done);
    expect(await s.downloadedChapters(mangaKey), [ch3, ch2, ch1, extra]);
    await s.deleteChapter(mangaKey, ch3.url);
    expect(await s.downloadedChapters(mangaKey), [ch2, ch1, extra]);
  });

  test('downloadedChapters breaks number ties by upload date', () {
    final old = ChapterInfo(
      url: '/a',
      name: 'a',
      number: 1,
      uploadedAt: DateTime.utc(2026),
    );
    final fresh = ChapterInfo(
      url: '/b',
      name: 'b',
      number: 1,
      uploadedAt: DateTime.utc(2026, 2),
    );
    const undated = ChapterInfo(url: '/c', name: 'c', number: 1);
    final sorted = [old, undated, fresh]..sort(newestFirst);
    expect(sorted, [fresh, old, undated]);
  });

  test('re-enqueueing a downloaded chapter does nothing', () async {
    final h = Harness();
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    await waitFor(s, ch1, DownloadStatus.done);
    await s.enqueue(mangaKey, ch1);
    expect((await s.watchAll().first).queue, isEmpty);
    expect(h.source.pageCalls, 1);
  });

  test('the queue survives a restart and resumes on start()', () async {
    final h = Harness();
    final first = h.service();
    await first.pause();
    await first.enqueue(mangaKey, ch1);
    await first.enqueue(mangaKey, ch2);
    final snap = await first.watchAll().first;
    expect(snap.paused, isTrue);
    expect(snap.queue.map((t) => t.chapter.url), [ch1.url, ch2.url]);

    final second = h.service();
    await second.start();
    expect((await second.watchAll().first).queue.length, 2);
    await second.resume();
    await waitFor(second, ch2, DownloadStatus.done);
    expect(await second.offlinePages(mangaKey, ch1.url), hasLength(3));
  });

  test('a failed page marks the chapter failed; retry finishes it', () async {
    final h = Harness(loader: FakeLoader(failures: 2));
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    final failed = await waitFor(s, ch1, DownloadStatus.failed);
    expect(failed.error, contains('flaky'));
    expect(h.failures.single, contains('flaky'));
    await s.retry(mangaKey, ch1.url);
    await waitFor(s, ch1, DownloadStatus.done);
    await s.retry(mangaKey, ch1.url); // no task any more: no-op
  });

  test('maxChapters limits chapters running at once', () async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(maxChapters: 1);
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await waitFor(s, ch1, DownloadStatus.downloading);
    expect(
      (await s.watch(mangaKey, ch2.url).first).status,
      DownloadStatus.queued,
    );
    h.loader.gate!.complete();
    await waitFor(s, ch2, DownloadStatus.done);
  });

  test('pause stops a running chapter; resume completes it', () async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(perHost: 1);
    await s.enqueue(mangaKey, ch1);
    await waitFor(s, ch1, DownloadStatus.downloading);
    await s.pause();
    h.loader.gate!.complete();
    await waitFor(s, ch1, DownloadStatus.queued);
    await s.resume();
    await waitFor(s, ch1, DownloadStatus.done);
  });

  test('cancel removes running and queued chapters and their blobs', () async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(maxChapters: 1);
    await h.blobs.put(pageBlobKey(mangaKey, ch2.url, 0), fakeImage('x'));
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await waitFor(s, ch1, DownloadStatus.downloading);
    await s.cancel(mangaKey, ch2.url);
    expect(await h.blobs.list(''), isEmpty);
    await s.cancel(mangaKey, ch1.url);
    h.loader.gate!.complete();
    await waitFor(s, ch1, DownloadStatus.none);
    await pumpEventQueue();
    expect(await h.blobs.list(''), isEmpty);
    expect((await s.watchAll().first).queue, isEmpty);
    await s.cancel(mangaKey, '/never'); // unknown: no-op
  });

  test('delete a chapter, then a whole manga; usage follows', () async {
    final h = Harness();
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await waitFor(s, ch1, DownloadStatus.done);
    await waitFor(s, ch2, DownloadStatus.done);
    final used = (await s.watchAll().first).index.totalBytes;
    expect(used, greaterThan(0));
    await s.deleteChapter(mangaKey, ch1.url);
    expect(await s.offlinePages(mangaKey, ch1.url), isNull);
    expect((await s.watchAll().first).index.totalBytes, used ~/ 2);
    await s.deleteManga(mangaKey);
    expect(await h.blobs.list(''), isEmpty);
    expect(await s.hasDownloads(mangaKey).first, isFalse);
    expect((await s.watchAll().first).index.totalBytes, 0);
  });

  test('cancel mid-chapter stops before the next page', () async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(perHost: 1);
    await s.enqueue(mangaKey, ch1);
    await waitFor(s, ch1, DownloadStatus.downloading);
    await s.cancel(mangaKey, ch1.url);
    h.loader.gate!.complete();
    await waitFor(s, ch1, DownloadStatus.none);
    await pumpEventQueue();
    expect(await h.blobs.list(''), isEmpty);
    expect(h.loader.calls.length, lessThan(3));
  });

  test('deleteManga also cancels its queued chapters', () async {
    final h = Harness();
    final s = h.service();
    await s.pause();
    await s.enqueue(mangaKey, ch1);
    await s.deleteManga(mangaKey);
    expect((await s.watchAll().first).queue, isEmpty);
  });

  test('watch can be cancelled before the store has loaded', () async {
    final s = Harness().service();
    final sub = s.watch(mangaKey, ch1.url).listen((_) {});
    await sub.cancel();
    await pumpEventQueue();
  });
}
