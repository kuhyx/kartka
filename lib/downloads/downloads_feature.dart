import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/downloads/auto/auto_downloader.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/engine/source_directory.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/downloads/ui/downloads_screen.dart';
import 'package:kartka/downloads/ui/downloads_tiles.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/platform.dart';

/// Route of the Downloads screen (opened from the More tab).
const downloadsRoutePath = '/downloads';

/// The downloads part: offline chapter store, queue UI, auto-download.
///
/// Supplies one [DownloadService] as both `DownloadRepository` (§8) and
/// the library's `DownloadedLookup` port. Downloads run while the app is in
/// the foreground; Android background workers are out of scope for v1.
KartkaFeature downloadsFeature(KartkaEnv env) {
  final p = env.platform;
  // The registry is only complete after every factory ran: read it lazily.
  final sources = SourceDirectory(() => env.registry.all<SourceProvider>());
  late final AutoDownloader auto;
  final service = DownloadService(
    kv: p.kv,
    blobs: p.blobs,
    engine: DownloadEngine(
      blobs: p.blobs,
      sourceFor: sources.find,
      loadPage: (page) => PageImageLoader(
        http: p.http,
        blobs: p.blobs,
        imageHeaders: env.registry.all<ImageHeaders>(),
      ).load(page),
    ),
    onLoaded: () => unawaited(auto.checkIfDue()),
    onFailure: downloadFailureReporter(DiagnosticsLog.of(p.diagnostics)),
  );
  Stream<List<LibraryEntry>> library() =>
      env.registry.maybe<LibraryRepositories>()?.library.watch() ??
      Stream.value(const []);
  // The toggle syncs (§16); queue, index and baselines stay local.
  final kv = syncedKv(env);
  auto = AutoDownloader(
    kv: kv,
    remoteChanges: kv.remoteChanges,
    library: library,
    findSource: sources.find,
    enqueue: service.enqueue,
  );
  return KartkaFeature(
    id: 'downloads',
    routes: [
      GoRoute(
        path: downloadsRoutePath,
        builder: (context, state) => DownloadsScreen(
          service: service,
          titles: library().map((l) => {for (final e in l) e.key: e.title}),
          onOpen: () => unawaited(auto.checkIfDue()),
        ),
      ),
    ],
    settingsTiles: [
      (context) => DownloadsNavTile(
        service: service,
        onOpen: () => unawaited(context.push(downloadsRoutePath)),
      ),
      (context) => AutoDownloadTile(auto: auto),
    ],
    services: [service],
  );
}

/// Logs a failed chapter download as `downloads.failed` with its source.
void Function(DownloadTask, Object, StackTrace) downloadFailureReporter(
  DiagnosticsLog log,
) =>
    (task, error, stack) => ErrorReporter.of(log).report(
      'downloads.failed',
      error,
      stack: stack,
      sourceId: splitMangaKey(task.mangaKey).$1,
    );
