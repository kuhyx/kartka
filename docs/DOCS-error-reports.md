# Kartka — error reports (app → RTDB → `fixme.md`)

Every error a user sees, and every exception that escapes, is reported to
the PC automatically and lands in `~/.local/state/kartka-errors/fixme.md`, a prompt a
future Claude session can paste to fix them. Builds on the diagnostics log
(`DOCS-contracts.md` §7).

## App side: one funnel, the diagnostics log

| Kind | Where it is caught |
|---|---|
| `uncaught.flutter`, `uncaught.async` | `installErrorReporting` (`lib/app/error_hooks.dart`, from `main`): chains `FlutterError.onError` and `PlatformDispatcher.onError`, skips `silent` details. No `runZonedGuarded` (zone mismatch after `ensureInitialized`). |
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
| existing kinds | `reader.advance`, `sync.error`, source installs: already in the log. |

Every entry is stamped with the go_router **pattern** on top
(`DiagnosticsLog.route`, set by `DiagnosticsRouteObserver`), never a
concrete location. `ErrorReporter` (`lib/core/diagnostics/`) is the door
for the global hooks: an identical `kind` + message inside 30 s is dropped
and at most 20 reports a minute are kept, so an error loop cannot flood
the log (which rewrites its file on every append).

## Transport: `/kartka-e2e/errors/<device>/<id>`

`ErrorUploader` (`lib/sync/error_upload.dart`, started by `syncFeature`):

- The log is the offline queue. `<id>` is the first 20 hex of sha1 over the
  entry's JSON, so a re-push is a no-op; ids pushed are kept in kv
  `errors.sent` (last 2500). `perf.*` entries are never uploaded.
- Sealed per report (DOCS-contracts §4; locked = not sent) and PATCHed
  straight through the sync transport (`SyncRuntime.transport`):
  no `revs/` bump, no change-feed entry, so no peer fetches it, and the
  engine never reads `errors/` (it GETs per namespace, never the root).
- Batches of 50, at most 200 per flush. Debounced 5 s after an append, and
  once 20 s after sync first starts (an earlier launch's backlog). A failed
  push backs off from 30 s to 15 min; signed out, it waits for the next
  append or launch. It never starts sync and never throws.
- `<device>` is `rtdbKey(crdt.nodeId)`. Every string goes through
  `redactForReport` first: URL queries, userinfo, emails, bearer/basic
  credentials, JWTs, `cookie|password|token|secret|api_key=...` values and
  the user name in `/home/<user>/` paths are masked.
- RTDB rules: the shared project pins `.read`/`.write` at the root to the
  one uid (`~/src/utils/firebase/database.rules.json`, rendered copy in
  `~/.config/crdt-sync/`), so the path needs no rule change.

## PC side: `tools/errors`

`tools/errors/run.sh ingest` (Python 3.15, uv, `crdt-sync` pinned like
`tools/source_eval`) signs in with the evaluator's seeded Google session
(`~/.config/kartka-source-eval/firebase_auth.json`; exit 3 names the seed
command when it is missing), reads `/kartka-e2e/errors` and opens each report
with the shared crdt-sync password (exit 4, nothing deleted, when locked;
no `kartka-e2e/e2e` header yet = nothing to read), merges every report
into `~/.local/state/kartka-errors/state.json`, saves it, rewrites
`fixme.md` (outside the repo; deleted when nothing is open), then deletes
exactly the `device/id` paths it read (never the whole node, which would
race with an upload). `--keep` skips the delete.

- **Signature**: error type (message prefix, or the Dart wording such as
  `Bad state` → `StateError`, else the kind) + the message with URLs,
  uuids, long hex and numbers masked + the first `package:kartka/` frame
  without line numbers (else the route, else the kind).
- **Resolve**: `tools/errors/run.sh resolve <signature>` after the fix is
  committed. A report newer than the fix reopens it.
- **Lock**: every command holds `state.json.lock` (flock) around
  load-modify-save, so a `resolve` during the timer's ingest is not lost.
- **First run**: a device's first upload is its whole existing log
  (up to 2000 entries), so the first TODO file can list old, fixed errors.
- **Timer**: `tools/errors/systemd/install.sh` installs
  `kartka-errors.{service,timer}` (user units, every 15 min, Persistent).
  `--verify-only`, `--uninstall`. Offline test:
  `tools/errors/systemd/test_install.sh`.
- Tests: `cd tools/errors && uv run pytest` (100 % branch coverage),
  `uv run ruff check`, `uv run mypy --strict src tests`.
