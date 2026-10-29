import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/engine/host_limiter.dart';
import 'package:kartka/downloads/engine/retry.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import 'fakes.dart';

const mangaKey = 'mangadex|/title/1';
const ch1 = ChapterInfo(url: '/chapter/1', name: 'Ch. 1', number: 1);
const ch2 = ChapterInfo(url: '/chapter/2', name: 'Ch. 2', number: 2);

/// Shared stores so a second service instance sees a "restarted app".
class Harness {
  new({FakeLoader? loader}) : loader = loader ?? FakeLoader();

  final MemoryKeyValueStore kv = MemoryKeyValueStore();
  final MemoryBlobStore blobs = MemoryBlobStore();
  final FakeSource source = FakeSource();
  FakeLoader loader;

  /// Every failure the service reported, as `<task id>: <error>`.
  final List<String> failures = [];

  DownloadService service({int maxChapters = 2, int perHost = 2}) =>
      DownloadService(
        kv: kv,
        blobs: blobs,
        maxChapters: maxChapters,
        onFailure: (task, e, _) => failures.add('${task.id}: $e'),
        now: () => DateTime.utc(2026, 10, 24),
        engine: DownloadEngine(
          blobs: blobs,
          loadPage: (p) => loader.call(p),
          sourceFor: (id) async => id == source.id ? source : null,
          limiter: HostLimiter(perHost: perHost),
          policy: const RetryPolicy(maxAttempts: 2),
          sleep: (_) async {},
        ),
      );
}

/// Waits until [service] reports [status] for [chapter].
Future<DownloadState> waitFor(
  DownloadService service,
  ChapterInfo chapter,
  DownloadStatus status,
) => service.watch(mangaKey, chapter.url).firstWhere((s) => s.status == status);
