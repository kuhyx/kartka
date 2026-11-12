import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/net/network_errors.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/downloads/auto/auto_downloader.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/download_titles.dart';
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
  final titles = DownloadTitles(kv: p.kv, findSource: sources.find);
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
          resolveTitle: titles.title,
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

/// How long a server's `downloads.offline` entry stands for every later
/// chapter that fails on it the same way.
const offlineReportWindow = Duration(minutes: 10);

/// Logs a failed chapter download with its source as `downloads.failed`.
/// A server that cannot be reached at all (`isOfflineError`) is logged as
/// `downloads.offline` instead, once per server ([serverOf]) per
/// [offlineReportWindow], so a queue failing chapter after chapter while
/// offline reports one entry, not one per chapter. The chapters still end
/// failed either way (Retry in the queue).
void Function(DownloadTask, Object, StackTrace) downloadFailureReporter(
  DiagnosticsLog log, {
  DateTime Function() now = DateTime.now,
}) {
  final offlineSince = <String, DateTime>{};
  return (task, error, stack) {
    final sourceId = splitMangaKey(task.mangaKey).$1;
    var kind = 'downloads.failed';
    if (isOfflineError(error)) {
      final server = serverOf(sourceId);
      final at = now();
      final since = offlineSince[server];
      if (since != null && at.difference(since) < offlineReportWindow) return;
      offlineSince[server] = at;
      kind = 'downloads.offline';
    }
    ErrorReporter.of(log).report(kind, error, stack: stack, sourceId: sourceId);
  };
}
