import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/engine/retry.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/platform/extension_runtime.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import '../fakes.dart';

/// A source whose page list the host cancels [cancels] times first.
class _CancelledList extends FakeSource {
  new(this.cancels);

  int cancels;
  final background = <bool>[];

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    background.add(isBackgroundCall);
    if (cancels-- > 0) throw const ExtensionCallCancelled();
    return await super.pages(chapterUrl);
  }
}

void main() {
  final task = DownloadTask(
    mangaKey: 'mangadex|/title/1',
    chapter: const ChapterInfo(url: '/chapter/9', name: 'Ch. 9'),
    enqueuedAt: DateTime.utc(2026),
  );

  // 64f0bd6f: download calls already in flight when a reader opened made
  // its page list and page 1 take 1 s each (0.2 s with none). The host now
  // cancels them when a shown page starts; the engine fetches them again.
  test('a call the host cancelled for a shown page runs again, '
      'after the shown page, costing no attempt', () async {
    final source = _CancelledList(1);
    final background = <bool>[];
    final cancelled = <String>{};
    var idles = 0;
    final done = await DownloadEngine(
      shownPageIdle: () async => idles++,
      blobs: MemoryBlobStore(),
      loadPage: (page) async {
        background.add(isBackgroundCall);
        if (cancelled.add(page.imageUrl)) {
          throw const ExtensionCallCancelled();
        }
        return fakeImage(page.imageUrl);
      },
      sourceFor: (_) async => source,
      policy: const RetryPolicy(maxAttempts: 1),
      sleep: (_) async => fail('a cancelled call is not a failure'),
    ).download(task, onProgress: (_) {});
    expect(done.pageCount, 3);
    expect(source.background, [true, true]);
    expect(background, [for (var i = 0; i < 6; i++) true]);
    // Each run waited for the shown page first: 2 list runs, 6 page runs.
    expect(idles, 8);
  });

  test('outside a download, calls are not background', () {
    expect(isBackgroundCall, isFalse);
    expect(runAsBackground(() => isBackgroundCall), isTrue);
  });
}
