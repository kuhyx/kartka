import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/engine/retry.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/platform/platform.dart';

import '../fakes.dart';

void main() {
  const key = 'mangadex|/title/1';
  const chapter = ChapterInfo(url: '/chapter/9', name: 'Ch. 9');
  final task = DownloadTask(
    mangaKey: key,
    chapter: chapter,
    enqueuedAt: DateTime.utc(2026),
  );
  late MemoryBlobs blobs;
  late FakeSource source;

  DownloadEngine engine(FakeLoader loader, {int maxAttempts = 3}) =>
      DownloadEngine(
        blobs: blobs,
        loadPage: loader.call,
        sourceFor: (id) => id == 'mangadex' ? source : null,
        policy: RetryPolicy(maxAttempts: maxAttempts),
        sleep: (_) async {},
        now: () => DateTime.utc(2026, 10, 24),
      );

  setUp(() {
    blobs = MemoryBlobs();
    source = FakeSource();
  });

  test('stores every page as a blob and reports progress', () async {
    final loader = FakeLoader();
    final progress = <DownloadState>[];
    final done = await engine(loader).download(task, onProgress: progress.add);
    final pages = fixturePages();
    expect(done.pageCount, 3);
    expect(done.chapterName, 'Ch. 9');
    expect(done.downloadedAt, DateTime.utc(2026, 10, 24));
    expect(
      done.bytes,
      pages.fold<int>(0, (s, p) => s + fakeImage(p.imageUrl).length),
    );
    for (final p in pages) {
      expect(blobs.data[pageBlobKey(key, chapter.url, p.index)],
          fakeImage(p.imageUrl));
    }
    expect(
      loader.headersSeen,
      anyElement(equals({'Referer': 'https://site-a.example/'})),
    );
    expect(progress.first, const DownloadState(
      status: DownloadStatus.downloading,
      pagesTotal: 3,
    ));
    expect(progress.last.pagesDone, 3);
  });

  test('retries a flaky page with backoff, then succeeds', () async {
    final loader = FakeLoader(failures: 2);
    final done = await engine(loader).download(task, onProgress: (_) {});
    expect(done.pageCount, 3);
    expect(loader.calls.values, everyElement(3));
  });

  test('gives up after maxAttempts and rethrows', () async {
    final loader = FakeLoader(failures: 5);
    await expectLater(
      engine(loader).download(task, onProgress: (_) {}),
      throwsStateError,
    );
  });

  test('a 404 is not retried', () async {
    final loader = FakeLoader(
      failures: 9,
      error: KartkaHttpException(Uri.parse('https://x'), 404),
    );
    await expectLater(
      engine(loader).download(task, onProgress: (_) {}),
      throwsA(isA<KartkaHttpException>()),
    );
    expect(loader.calls.values, everyElement(1));
  });

  test('429 and 5xx are retried', () {
    expect(isRetryable(KartkaHttpException(Uri(), 429)), isTrue);
    expect(isRetryable(KartkaHttpException(Uri(), 503)), isTrue);
    expect(isRetryable(KartkaHttpException(Uri(), 403)), isFalse);
    expect(isRetryable(const DownloadStopped()), isFalse);
    expect(isRetryable(StateError('net')), isTrue);
  });

  test('resumes: pages already stored are not fetched again', () async {
    final first = fixturePages().first;
    await blobs.put(pageBlobKey(key, chapter.url, 0), fakeImage('old'));
    final loader = FakeLoader();
    final done = await engine(loader).download(task, onProgress: (_) {});
    expect(loader.calls.containsKey(first.imageUrl), isFalse);
    expect(done.pageCount, 3);
  });

  test('stops before fetching when shouldStop turns true', () async {
    final loader = FakeLoader();
    await expectLater(
      engine(loader).download(task, onProgress: (_) {}, shouldStop: () => true),
      throwsA(isA<DownloadStopped>()),
    );
    expect(loader.calls, isEmpty);
  });

  test('unknown source and empty chapter fail clearly', () async {
    final orphan = DownloadTask(
      mangaKey: 'gone|/m',
      chapter: chapter,
      enqueuedAt: DateTime.utc(2026),
    );
    await expectLater(
      engine(FakeLoader()).download(orphan, onProgress: (_) {}),
      throwsA(isA<StateError>()),
    );
    source = FakeSource(pages: const []);
    await expectLater(
      engine(FakeLoader()).download(task, onProgress: (_) {}),
      throwsA(isA<StateError>()),
    );
  });
}
