# CLAUDE.md — kartka

Private manga reader (Flutter 3.47.7 via fvm; Android + web). Read
`SPEC.md` (goal, structure, boundaries) and `docs/DOCS-contracts.md` (the
interfaces every part codes against) before changing anything shared.

The **desktop app is the web build** in a Chrome `--app` window, served by
the local wrapper in `desktop/` (a separate pure-Dart package). Do not add
`linux/`: `flutter create --platforms linux` silently restores the GTK
embedder, which manages ~20 fps at 4K.

## Commands

- run: `./run.sh` (desktop; `./run.sh android` builds, `adb install -r`s and launches)
- test: `fvm flutter test --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: `fvm dart analyze --fatal-infos && fvm dart format --set-exit-if-changed lib test desktop`
- coverage: `scripts/coverage.sh`
- coverage-gaps: `coverage-gaps coverage/lcov.info`

Inner loop: `~/.claude/scripts/capped.sh fvm flutter test <changed paths>`.
A whole-suite run under `capped.sh` can be SIGTERMed by the shared memory
ceiling (the runner still prints errors); `scripts/coverage.sh` runs one
test directory at a time for that reason. Wrapper package:
`cd desktop && fvm dart test` / `fvm dart analyze --fatal-infos`.

## Layout

- `lib/core/` pure Dart: models (§1, §8), `MangaSource`, `SourceProvider`,
  repository interfaces. Models are immutable, compare instants by moment,
  and write UTC ISO-8601.
- `lib/platform/` the seam (§7, §11). `createPlatform()` picks `io/`
  (Android) or `web/` (desktop) by conditional import. `memory/` holds the
  in-memory fakes every part's tests use (`memoryPlatform()`,
  `FakeKartkaHttp`).
- `lib/app/` registry (`kartkaFeatureFactories`, append-only), shell
  (Library / Browse / Sources / More), routes, `KartkaScope`.
- `desktop/` the wrapper: static build, `/proxy`, `/files`, `/secrets`,
  `/oauth`, on `127.0.0.1:47391`.
- Feature dirs (`lib/sources`, `lib/library`, `lib/reader`, ...) belong to
  their parts; foundation never imports them.

## Rules that are enforced by tests

- No `dart:io` in `lib/` outside `lib/platform/io/`; `package:web` /
  `dart:js_interop` / `idb_shim` only in `lib/platform/web/`;
  `package:http` and `file_picker` only in `lib/platform/`
  (`test/platform/import_boundaries_test.dart`).
- Every `lib/` file is imported by `test/all_imports_test.dart` unless it is
  `// coverage:ignore-file` thin wiring (with a reason), so lcov cannot
  silently omit a file. 100 % line coverage (`scripts/check_coverage.py`).
- The wrapper port is defined once, `kartkaWrapperPort` in
  `lib/platform/wrapper_protocol.dart`; `desktop/test/protocol_test.dart`
  fails if the wrapper's copy differs. It must stay fixed: the browser keys
  IndexedDB by origin and the OAuth redirect is registered for it.
- The User-Agent is honest (`kartkaUserAgent`), never a browser string, and
  carries no personal data.

## Wrapper security model

Loopback bind only, plus: foreign `Host` → 421 (DNS rebinding), cross-site
`Origin` on writes → 403, API routes need `x-kartka: 1` (a cross-site page
cannot add it without a preflight, and OPTIONS is never granted), no
`Access-Control-Allow-Origin` anywhere. `/proxy` forwards only allow-listed
headers, never `Via` / `X-Forwarded-*`, always the Kartka UA. Secrets live in
`~/.config/kartka/secrets.json` at 0600, never in browser storage.

## Conventions

- Dart 3.13 constructor syntax (`const new(...)`, `factory fromJson(...)`):
  very_good_analysis flags the old form.
- 250-line cap per file, code and prose (pre-commit + CI).
- Exact pins, newest stable (`scripts/check_dependency_freshness.sh`).
- Commits: `<area>: <imperative summary>` + attribution trailer. Never
  `--no-verify`.
- Phone: `adb install -r` only. Never uninstall or `pm clear` (wipes the
  library).
- UI tokens come from `design_system` (kuhyx/utils): no local colours.
