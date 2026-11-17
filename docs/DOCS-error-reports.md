# Kartka — error reports (app → RTDB → board ticket)

Every error a user sees, every exception that escapes and every wait over
1 s is reported to the PC automatically, where the shared `app-errors`
ingest (kuhyx/utils `DOCS-app-errors.md`) turns each signature into a
self-fixing board ticket. Since 2026-11-17 kartka uses the shared reporter
(crdt_sync_flutter 0.9.1); its own uploader, hooks and ingest are retired.
The device log (`DOCS-contracts.md` §7) stays kartka's.

## App side: one funnel, the diagnostics log

| Kind | Where it is caught |
|---|---|
| `uncaught.flutter`, `uncaught.async` | crdt_sync_flutter `installAppErrors` (from `main`): chains `FlutterError.onError` and `PlatformDispatcher.onError`, skips `silent` details; queued straight for upload (not in the device log). |
| `ui.snackbar` | `ReportingScaffoldMessenger`, mounted in `MaterialApp.builder` (`lib/app/app.dart`), so it is the nearest messenger of every route. An error is a snackbar with the danger hue (design_system `showError`) or failure text (`failed`, `Exception`, `unavailable`, ...). |
| `reader.open` | `ReaderSession.open` (the reader's Retry screen). |
| `reader.page` | `ReaderSession.image` (a page's Retry); background prefetch stays quiet. |
| `downloads.failed` | `DownloadService.onFailure` (the queue's Retry), wired by `downloadsFeature`. |
| `downloads.offline` | `downloadFailureReporter`: a server that cannot be reached (`isOfflineError`), once per server per 10 min, not once per chapter. |
| `plugins.repo` | `PluginManager.onRepoError` (the per-repo error list on More → Plugins). |
| `health.read` | `ReportingHealthFeed`, around the Sources tab's feed only (not the badges). |
| `details.load`, `details.refresh` | `MangaDetailController.load` / `refresh`. |
| `browse.page` | `PagedController.onError`, wired by `SourceScreen` (the grid's Retry). |
| `suwayomi.extensions` | `ExtensionsScreen._load` (its Retry screen). |
| `perf.slow` | crdt_sync_flutter `WaitWatch`, wrapped around every page-level loader; see "Slow waits" below. |
| existing kinds | `reader.advance`, `sync.error`, source installs: already in the log. |

Every entry is stamped with the go_router **pattern** on top
(`DiagnosticsLog.route`, set by `DiagnosticsRouteObserver`), never a
concrete location. `ErrorReporter` (`lib/core/diagnostics/`) is the door
for the global hooks: an identical `kind` + message inside 30 s is dropped
and at most 20 reports a minute are kept, so an error loop cannot flood
the log (which rewrites its file on every append).

## Upload and ingest (shared)

`lib/app/app_errors.dart` wires it (`main` installs, `syncFeature`
connects):

- `bridgeDiagnostics` queues a device-log entry for upload only when
  `isUploadedEntry` (`lib/core/diagnostics/upload_rule.dart`) holds and it is
  not `perf.*` / `uncaught.*` (the shared hooks' own). Environment states
  (`isEnvironmentError`: no DNS or route, a dropped or refused connection, a
  500/502/503/504 from our server, its upstream unknown or its WebView
  timing out, a manga the server no longer has) stay on the device: the
  screens show them; a ticket could not fix them.
- `ErrorRouteObserver` stamps the go_router pattern into the shared
  reporter, so perf.slow signatures (kind + route + operation) are the
  same as before.
- The shared `ErrorUploader` writes `/kartka/errors/<device>/<id>` through
  `errorSink` (`lib/sync/error_sink.dart`, kartka's signed-in transport,
  sandbox namespace included), with `build` / `version` from
  `--dart-define=APP_BUILD/APP_VERSION` (`build_android.sh`,
  `build_web.sh`), else the installed versionCode. Queue: SharedPreferences.
- PC: `app-errors-ingest.timer` (kuhyx/utils `app_errors`) reads `/kartka`
  too, writes `~/.local/state/app-errors/kartka.json`; resolve with
  `app-errors resolve kartka <signature>`. All 134 stored kartka
  signatures recompute identically there.
- Agent checks: `tools/agent/uploadable.dart <log>` applies the same rule
  to a device log.

## Slow waits (`perf.slow`)

Every wait the user sees for over 1 s is reported, so a ticket can drive it
under 1 s. `WaitWatch(operation, child)` (crdt_sync_flutter) wraps a
spinner; it times how long the spinner stays mounted.

- A wait of 1 s or less writes nothing. A longer one writes an entry at its
  end: `kind` `perf.slow`, `route` (the pattern on top when it began),
  `operation`, `durationMs`, `waitId`. One still going after 5 s writes at
  once with `still: true`, and its end writes again under the same `waitId`.
  At most 30 entries a minute. Before `installAppErrors` (widget tests): no-op.
- Hooked: `reader.open`, `reader.page`, `reader.chapter`, `library.load`,
  `updates.load`, `details.load`, `details.refresh`, `suwayomi.extensions`,
  `downloads.load`, `sources.load`, `browse.nextpage`, `search.global`,
  `plugins.load`, `tracking.search`, `sync.start`. Not hooked: button and
  tile spinners (an install or import is meant to take a while), determinate
  bars (downloads, update strip, import), the migration screens.
- **Signature** = kind + route + operation only, never the time, so all slow
  waits of one operation are one ticket. A `still` report and its final
  report count as one wait (`device/waitId`); the record keeps the last 200.
