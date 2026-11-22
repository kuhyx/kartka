# Kartka — spec

Private `kuhyx/kartka`. Own manga reader replacing the dropped TachiyomiSY fork
(too big to bring to kuhy's standards; Kotlin; not desktop-first). Small, Dart,
desktop-friendly from day one. Contracts every part codes against:
[`DOCS-contracts.md`](DOCS-contracts.md).

## Goal and done (v1)

On the Pixel 6a (`23181JEGR08034`) AND the desktop Chrome-app build:

1. Import the current SY backup (`.tachibk`): every library entry appears with
   its categories and the right last-read chapter.
2. Read a chapter **offline** (airplane mode) from every kept source and from a
   local CBZ.
3. Progress made on one device shows on the other within 10 s (Firebase RTDB).
4. Reading a chapter updates the AniList entry (and MAL / MangaUpdates when linked).
5. Install a converted Mangayomi JS plugin from a repo URL and read with it.
6. Read a chapter through the self-hosted Suwayomi server.
7. Browse → Sources shows the source-health ranking (every metric, verdict, cut
   reasons) and badges on each source, fed by the weekly source evaluator.
8. `flutter test` green, 100 % line coverage on logic under `lib/` (UI widgets
   have widget tests), APK installed with `adb install -r` (never uninstall).

## Stack

- Flutter **3.50.1** pinned in `.fvmrc`, Dart from that SDK. Exact pins in
  `pubspec.yaml`, newest stable, lockfile committed, dependency-freshness gate.
- Targets: Android + web. "Desktop" = web build in a Chrome `--app` window served
  by a local Dart wrapper (pattern + traps: skill `flutter-desktop-to-chrome`).
  **No `dart:io` in `lib/` outside `lib/platform/io/`** (conditional imports).
- Sync: `crdt_sync_flutter` (kuhyx/utils, latest tag) → Firebase RTDB only,
  shared credential `~/.config/crdt-sync/`, per-install device id.
- Sources: (b) native Dart sources (MangaDex first), (c) Suwayomi-Server client
  (runs Keiyoushi/Tachiyomi extensions), (d) local CBZ/folders, plus JS plugins.
- Plugins: JS with kartka's own small API (QuickJS on Android, browser JS in a
  worker on web) + a converter for Mangayomi JS extensions.
- Tracking: AniList + MyAnimeList (OAuth) + MangaUpdates (login), two-way, progress never decreases.
- Source evaluator: Python (newest CPython, typed, pytest) in `tools/source_eval/`.
- Suwayomi deploy: `deploy/suwayomi/` (install.sh, systemd unit, Caddy block
  with basic auth) on the host that already runs syncyomi.

## Structure

```
lib/app/            app shell, routes, feature registry (one list, append-only)
lib/core/           models, MangaSource interface, repositories (pure Dart)
lib/platform/       seam: io/ (Android, wrapper) vs web/ implementations
lib/sources/        mangadex/  suwayomi/  local/
lib/plugins/        runtime/ (host API, QuickJS + web worker)  mangayomi/ (converter)
lib/library/        library + categories screens and state
lib/reader/         paged (LTR/RTL) + webtoon reader, prefetch
lib/downloads/      offline chapter store + queue
lib/sync/           crdt_sync_flutter wiring, RTDB mappers
lib/tracking/       anilist/  mal/  common/
lib/backup_import/  .tachibk decoder + mapper
lib/source_health/  ranking screen, badges, RTDB reader
lib/migration/      walk the library one by one onto the best source
lib/perf/           per-screen jank tracker → diagnostics log, More → Performance
lib/updates/        Updates tab: new-chapter feed, shared "update all" run
desktop/            local wrapper server (static web build + /proxy + files)
tools/source_eval/  Python evaluator (probe, metrics, publish)
deploy/suwayomi/    server install
test/               mirrors lib/; test/e2e/ for on-device flows
```

## Auto-shelving (kuhy, 2026-11-21; defaults logged here)

`AutoShelver` (`lib/library/state/`) moves stale entries on its own:

- Stale: the newest stored chapter `uploadedAt` is over 18 calendar months
  old (`staleCutoff`, day clamped). No dated chapter: never moved
  (`LibraryEntry.updatedAt` is a sync clock, not a chapter date). No stored
  list: each run first fetches the lists of the 20 oldest-added such entries
  (`ChapterBackfill`, `lib/core/updates/`: 2 at a time, 1 per source; a failed
  one waits behind the untried and logs device-only `library.backfill`).
- All read: the category named `finished` (trimmed, any case), else one
  created as `finished`. Some unread: the first by order whose name holds
  `abandon` or `complet`, else one created as `abandoned`. Created ones get a
  fixed id (`autoshelve.<shelf>`), so two devices make one category.
- A move puts the entry in that category only: every other membership is
  removed, also when it was already in the shelf (counted as moved then).
- Memory: synced setting `library.autoshelve` (contracts-runtime §16), key to
  the newest upload seen shelved. Until a strictly later upload the entry is
  never moved again, so a manual move-out sticks on every device. Entries
  found already shelved are remembered too; a device with no or an older
  stored list keeps the entry as is; a non-stale newest upload clears it.
  The node is one LWW map: two devices writing in the same sync window can
  drop an entry, which the next run re-adds while it is still shelved.
- When: after every finished update-all run, and once per launch after the
  Library's first paint unless a run ended under 6 h ago (device-local
  `library.autoshelve.lastRun`). Never awaited by a screen.
- Feedback: none on screen. A run that moved something logs one
  device-only `library.autoshelve` line, counts only.

## Duplicate merging (kuhy, 2026-11-21; defaults logged here)

`LibraryDeduper` (`lib/migration/dedupe/`) merges entries that are
literally the same series onto the one on the best source, on its own:

- Pair: two entries on different sources whose titles (alt titles too)
  score >= 0.95 with the `SameManga` matcher (every word of each must
  match the other, so "X 2" never pairs) and no evidence disagrees: authors
  when both list some; stored chapter counts within 10 % or 3; descriptions
  when both have one (`descriptionScore` under 0.2 vetoes). Neither side
  with an author or a description: uncertain, skipped. Entries are judged
  on the chapter list this device stored (browse's `DupeFactsLookup`); the
  shared `ChapterBackfill` first fetches missing ones, as above. One source counts too when its two urls name the same
  manga (`sameListing`: every path segment and query value of one, generic
  words like `manga` aside, is among the other's), e.g. a bare id `abc`
  next to `/manga/abc/slug`; other urls on one source never pair.
- Winner: keep, then pending, then cut; a source not installed or with no
  record last. Then evaluator rank (ranked tiers only), more chapters,
  newer newest chapter, stored details, key. Three or more: each loser is checked against
  the winner directly.
- Merge: one `exportBackup` per run before the first merge (a failed backup
  merges nothing). The winner keeps the earlier `addedAt` (fresh
  `updatedAt`), gets every chapter number read on the loser marked read,
  the further progress, the union of categories, and the loser's tracker
  bindings for services it lacks. Downloads stay. Then the loser is removed.
- When: after every finished update-all run, and once per launch on the
  Library's first load (`LibraryStartTask`) unless a run ended under 6 h
  ago (device-local `library.dedupe.lastRun`). No ranking or no installed
  source: no run, gate left open. Never awaited by a screen; no dialog.
- Feedback: none on screen. A run that merged logs one device-only
  `library.dedupe` line, counts only.

## Reader advance (19643be5; defaults logged here)

The next chapter's page 1 shows within 1 s of swiping past the last page.
The stored chapter list names the next chapter once page 1 is in, so its
page list loads beside the fresh list; the fresh list wins, and a loaded
chapter it no longer puts next is dropped unless the reader is in it. The
chapter after a short one starts once fewer than max(prefetch, 5) loaded
pages are left. An edge wait over 1 s logs `ReaderProbe: next chapter
waited on list|pages|retry` (`reader.advance`). Live check:
`tools/agent/flows/f6_chapter_advance.sh`.

## Commands

- Run: `./run.sh` (desktop Chrome app), `./run.sh android`.
- Test: `~/.claude/scripts/capped.sh fvm flutter test <changed paths>` inner
  loop; full `fvm flutter test --coverage` at the end.
- Lint: `fvm dart analyze --fatal-infos`, `fvm dart format --set-exit-if-changed .`
- Python: `uv run pytest tools/source_eval`, `uv run ruff check`, `uv run mypy --strict`.
- Phone: skill `phone-deploy` (`adb install -r`, never uninstall / pm clear).

## Testing

`flutter_test` + `glados` property tests for parsers/mappers/merge rules
(skill `property-and-differential-tests`). HTTP sources tested against recorded
fixtures in `test/fixtures/<source>/` — no live network in unit tests. One
live smoke test per source tagged `@Tags(['live'])`, excluded by default.

## Style

`very_good_analysis`, 250-line cap per file (code and prose), small typed
helpers, docs on public API. Match `~/src/todo` for app/sync idioms and
`~/src/utils/unified-design-system` for UI tokens. Family launcher icon (skill
`app-icon`). Markdown namespaces per skill `md-file-conventions`.

## Git

Work lands on `main` (kuhy works on main). Parallel agents use worktrees on
`agent/<part>` branches; the coordinator merges to main and pushes. Commit
format: `<area>: <imperative summary>` + attribution trailer. Never
`--no-verify`. `install_repo_contract_gate.sh` installed after `git init`.

## Boundaries

- ✅ Always: red check first, fixtures over live calls, capped heavy commands,
  respect each site's rate limits (≤1 req / 2 s per host in the evaluator).
- ⚠️ Ask first: anything on the live server outside the Suwayomi unit/Caddy
  block; publishing anything public; new paid services.
- 🚫 Never: second sync transport (no GitHub mirror), uninstalling the app on
  the phone, committing secrets/tokens, vendoring Mangayomi/Tachiyomi code
  without checking its licence, bypassing captchas/Cloudflare challenges
  (a challenged source is measured as "blocking", not defeated).
