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
| `reader.open` | `ReaderSession.open` (the reader's Retry screen); not a chapter neither downloaded nor fetchable (`ChapterUnavailable`). The reader's probe adds the cause with the source id: `ReaderProbe: <sourceId> listed no pages`, or `first 3 images failed on <sourceId>: <error>` (`FirstImagesProbe`). |
| `reader.page` | `ReaderSession.image` (a page's Retry); background prefetch stays quiet. |
| `downloads.failed` | `DownloadService.onFailure` (the queue's Retry), wired by `downloadsFeature`; not a source nothing lists (`UnknownSourceError`). |
| `downloads.offline` | `downloadFailureReporter`: a server that cannot be reached (`isOfflineError`), once per server per 10 min, not once per chapter. |
| `plugins.repo` | `PluginManager.onRepoError` (the per-repo error list on More → Plugins). |
| `health.read` | `ReportingHealthFeed`, around the Sources tab's feed only (not the badges). |
| `details.load`, `details.refresh` | `MangaDetailController.load` / `refresh`. |
| `browse.page` | `PagedController.onError`, wired by `SourceScreen` (the grid's Retry). |
| `suwayomi.extensions` | `ExtensionsScreen._load` (its Retry screen). |
| `perf.slow` | crdt_sync_flutter `WaitWatch`, wrapped around every page-level loader; see "Slow waits" below. |
| `sources.autoupdate` | `ExtensionAutoUpdater` (`lib/source_health/install/`): one summary per run, counts and package names only (`updated 6 [..], failed 1 [..]`); a run with no failure stays on the device (`isUploadedEntry`). |
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
  not `perf.*` / `uncaught.*` (the shared hooks' own). `deviceOnlyKinds`
  (`library.autoshelve`, `library.dedupe`: records of a move or merge)
  never go up. Environment states
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
under 1 s. `ShownWaitWatch(operation, child)` (`lib/app/`) wraps a
spinner in crdt_sync_flutter's `WaitWatch`, which times how long it stays
mounted, but only while its tickers run: a page under a pushed route or
in a hidden tab is not timed. A refresh bar over readable stored chapters
is not a wait either, nor the pager's neighbour pages built off screen.
`reader.page`: the server rate-limits a source (4 pages at once took up
to 1.95 s each, one at a time 0.15 s; 28fffd0a), so `PageCache.focus`
fetches the shown page alone, then the look-aheads one at a time. No page
widget or decode plan starts a fetch beside it (`PageCache.waitFor`): the
pager's off-screen neighbour and the webtoon cache extent made it 3-19 at
once. The reader asks for the chapter list only once page 1 is in (beside the open
it slowed page 1 from 0.3-0.8 s to 2.9-4.0 s).
Opening a chapter online from a WebView source waited ~20 s on the
server's own upstream fetch (971debc8; AllManga: `DOCS-suwayomi.md`, KCEF
section). `PageListCache` marks a source whose page list timed out on a
WebView in kv with no expiry (a marked source is never fetched, so a lapsing
mark cost one more reported 20 s open per device), and later opens show the
Retry screen at once, unreported; Retry asks again and a success clears the
mark. Sources known broken on our server (`PageListCache.knownBroken`:
AllManga) start marked, so even the first open pays nothing, until one
Retry succeeds. The mark is checked before an in-flight fetch is joined:
on build 591 a Retry's 20 s fetch was still running when the chapter was
opened again, and the open joined it. Once a manga's details load, `PageWarmSlot` fetches the
Continue chapter's page list (the progress chapter, else the first unread
one) ahead into the same cache, so Continue opens without the 2-4 s
upstream fetch, then its first 3 page images from the saved page, one at
a time, into `PageImageWarmer`: the reader loads every image through it,
so the first pages draw at once (a MangaFire page costs 0.5-0.9 s on the
server; 28fffd0a). The Updates sheet skips the details screen, so opening
it warms the same way (`ChapterWarmer`) the chapter a tap most likely
opens: the newest unread one, else the newest (a cold open took 1.2 s).
The feed warms its first 3 tiles the same way as it shows: a tap soon
after the sheet opened still joined a cold page list (1.7 s on f4).
`SourceLookup` subscribes to every provider once and keeps their lists:
each open re-listed every provider one after another, so a slow runtime
added up to 5 s (build 615) and a cold miss took 0.83 s. The reader's two
synced-kv prefs reads (0.33 s on web) run beside the page list.
`browse.nextpage`: the server's source rate limiter is shared by its
thumbnails and its pages, so a grid's 50 uncached covers (up to 25 s each
on MangaFire) put the next page 8-41 s behind them (89e1ec6e).
`CoverCache.maxLoads` runs 2 cover loads per host at once, newest first:
a page then waits behind at most 2 (1.2-1.6 s, fetched a page ahead).
`tools/agent/flows/f4_reader_sweep.sh` opens the newest chapters on
Updates headless and fails on any open over 1 s.

- A wait of 1 s or less writes nothing. A longer one writes an entry at its
  end: `kind` `perf.slow`, `route` (the pattern on top when it began),
  `operation`, `durationMs`, `waitId`. One still going after 5 s writes at
  once with `still: true`, and its end writes again under the same `waitId`.
  At most 30 entries a minute. Before `installAppErrors` (widget tests): no-op.
- Hooked: `reader.open`, `reader.page`, `reader.chapter`, `library.load`,
  `updates.load`, `details.load`, `details.refresh`, `details.chapters`
  (fresh details shown, the chapter list still loading; 9f7cad2f),
  `suwayomi.extensions`,
  `downloads.load`, `sources.load`, `browse.nextpage`, `search.global`,
  `plugins.load`, `tracking.search`, `sync.start`. Not hooked: button and
  tile spinners (an install or import is meant to take a while), the
  reader's spinner after Retry (a probe of a source that just failed), determinate
  bars (downloads, update strip, import), the migration screens.
- **Signature** = kind + route + operation only, never the time, so all slow
  waits of one operation are one ticket. A `still` report and its final
  report count as one wait (`device/waitId`); the record keeps the last 200.
