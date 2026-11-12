# Kartka — contracts, §5 (source health)

Split out of [`DOCS-contracts.md`](DOCS-contracts.md) (§1-§9) to keep both
under the line cap; same rules. Implementation notes:
[`DOCS-source-eval.md`](DOCS-source-eval.md).

## 5. Source-health record (evaluator → RTDB → app UI)

```json
{
  "id": "suwayomi:2499283573021220255", "name": "MangaDex", "lang": "en",
  "origin": "suwayomi", "probedAt": "2026-10-24T12:00:00Z",
  "uptime": {"windowDays": 7, "probes": 28, "ok": 27, "ratio": 0.964,
             "status": "accruing|final"},
  "latencyMs": {"p50": 420, "p95": 1300},
  "blocking": {"challengeRate": 0.0, "kinds": ["cloudflare","captcha","403","429"]},
  "coverage": {"referenceSize": 650, "found": 512, "ratio": 0.788},
  "chapterCompleteness": {"sampled": 40, "medianRatio": 0.97},
  "imageQuality": {"sampledPages": 120, "medianWidthPx": 1100,
                   "medianJpegQuality": 88},
  "pagesLoad": {"ratio": 1.0, "sampled": 10},
  "langScope": "en+ja|unrestricted",
  "subsetOf": {"sourceId": "mangadex", "overlap": 0.93},
  "score": 0.852, "defaultScore": 0.852, "rank": 3,
  "verdict": "keep|cut|pending",
  "cutReasons": ["uptime<0.95", "blocking", "coverage<0.60", "subset"],
  "flags": ["needs-browser-engine"]
}
```

- **Reference set**: titles in the SY backup + AniList top 500 manga by
  popularity, stored at `tools/source_eval/data/reference.json`.
- **Languages**: candidates are English, Japanese and multi-language (`all`)
  sources only. `langScope` says what was measured: `en+ja` for a
  single-language en/ja source (and native MangaDex, English feed);
  `unrestricted` for an `all` source, measured as the backend serves it (no
  backend restricts one to en/ja yet). Japanese sources are searched by the
  AniList native title first and also matched against it.
- **Chapter completeness**: source chapter count / AniList (fallback
  MangaUpdates) chapter count for sampled reference titles, capped at 1.
- **pagesLoad** (added 2026-10-25): share of the sampled chapters whose page
  images all downloaded (`ratio`), over `sampled` attempted chapters. A chapter
  whose page list failed, came back empty, or had an image fail counts as not
  loaded. `ratio` is `null` when no chapter was attempted.
- **Subset**: ≥ 90 % of a source's found titles also found by a higher-ranked,
  not-cut source with ≥ its image quality → `subsetOf` set and `subset` added
  to `cutReasons` (explanatory only, see Verdict).
- **Cut reasons**: `uptime<0.95` (ratio < 0.95, only once `final`),
  `blocking` (challengeRate > 0 from any kind other than `webview`),
  `coverage<0.60`, `subset`. They are computed and published in `cutReasons`
  to explain a low score and the UI shows them. Whether one also **cuts** is
  the active profile's call (below); under the DEFAULT profile none does.
  Page loading has no reason code: it lowers the score, and the profile's
  `pagesNeverLoad` switch reads `pagesLoad.ratio == 0`.
- **Scoring profile** (2026-10-25, kuhy's decision): user-tunable, one active
  profile for the app and the evaluator.

  ```json
  {"weights": {"coverage": 0.30, "chapterCompleteness": 0.20, "uptime": 0.20,
               "imageQuality": 0.15, "speed": 0.15},
   "pagesLoadMultiplier": true, "keepScore": 0.90,
   "cuts": {"blocking": false, "subset": false, "coverage": false,
            "uptime": false, "needsBrowserEngine": false,
            "pagesNeverLoad": false}}
  ```

  Weights are 0..1 each (0 turns a part off) and are **normalised to sum 1**
  when scoring; all-zero weights are invalid. `keepScore` is 0..1. A missing
  field takes its DEFAULT and unknown keys are ignored; a field of the wrong
  type, a weight or `keepScore` outside 0..1, or all-zero weights make the
  **whole profile invalid** (readers fall back to DEFAULT, the evaluator with
  a warning). The values above are the **DEFAULT profile**: the evaluator's
  historic constants, immutable, always available in both the app ("Reset to
  evaluator defaults") and the evaluator (`--weights default`).
  `speed` is the former latency part. Two definitions exist, one per
  language (`tools/source_eval/src/source_eval/profile.py`,
  `lib/source_health/scoring/profile.dart`), pinned together by
  `tools/source_eval/tests/fixtures/scoring_profile.json`, which both test
  suites read (defaults, parse cases, golden scores, verdicts and ranks).
- **Score**: Σ normalisedWeightᵢ × partᵢ, then × `pagesLoad.ratio` when the
  profile's `pagesLoadMultiplier` is on and the ratio is not `null` (so with
  it on, a source whose pages never load scores 0). Parts: coverage ratio,
  chapter-completeness median, uptime ratio, image quality (width/1400 capped
  at 1), speed (1 − p95/5000, floored at 0); an unmeasured part is 0. Rounded
  to 3 places. `score` is under the **active** profile; `defaultScore` is the
  same record under DEFAULT (equal under DEFAULT, and the app shows it next
  to a custom score when they differ).
- **Verdict**: any cut switch the profile enables whose reason applies → `cut`
  (reasons: `blocking`, `subset`, `coverage`, `uptime` from `cutReasons`;
  `needsBrowserEngine` = the `needs-browser-engine` flag; `pagesNeverLoad` =
  `pagesLoad.ratio == 0`); else score ≥ `keepScore` → `keep`; else `pending`
  while unmeasured (`coverage.ratio` is `null`); else `cut`. DEFAULT has every
  switch off, so there the score alone decides (2026-10-25) and a `keep` may
  carry `cutReasons` (warnings). Uptime still accruing does not force
  `pending`. `subsetOf` is computed by the evaluator (it needs every source's
  found titles) under the profile it ran with; the app never recomputes it,
  it re-scores, re-ranks (rank tier, then score, then origin native <
  suwayomi < plugin, then id) and re-judges from the published metrics and
  `cutReasons`.
- **Rank tier** (2026-10-29): the `needs-browser-engine` flag and any
  `blocking*` cut reason each add 1 (0..2), and ranking sorts by it before the
  score, so such a source ranks below every source without it and both
  lowest. Score and verdict are unchanged: a usable KCEF source stays `keep`.
  The base ranking for `subsetOf` uses it too. `source_eval/tier.py` and
  `rankTier` (`score_breakdown.dart`); the detail page's score breakdown says
  why. A pre-flag record (`webview` kind, no `flags`) is not tiered.
- **App** (2026-10-25): Sources has a "Scoring" button opening the Scoring
  page: a slider per weight (0 = off) with its share after normalisation, an
  "Only this" button per weight (zeroes the others; a zero weight becomes 1),
  the pages-load switch, the keep-bar slider, one switch per cut reason, and
  "Reset to evaluator defaults". Weights cannot all reach 0 (the slider
  snaps back). The profile is the synced setting above, so every device
  shares it. A `ScoredHealthFeed` re-scores the published records with it
  (unchanged when the run's `meta.profile` already equals it), so the
  Sources ranking, its counts and Browse's badges all follow it live. A
  card shows `default 0.85` next to a custom score that reads differently.
- **As built** (evaluator, 2026-10-24): every record also carries
  `availability: {native, mangayomiJs, keiyoushi}` (bools: where else the
  source can be read). `blocking.kinds` may also list `webview` (the extension
  needs a browser engine; recorded, never defeated). `webview` is **flagged,
  not cut** (decision 2026-10-24): it still counts in `challengeRate` and
  `kinds`, but a record whose only kind is `webview` is not cut for
  `blocking`; any other kind next to it still cuts. `flags` is an additive
  list of non-cutting warnings (absent = none; readers tolerate it missing and
  keep unknown entries). The only flag today is `needs-browser-engine`, set
  whenever `webview` challenges were seen. The app shows a "Needs browser
  engine" chip on the Sources row, the detail page and the Browse badge.
  **`reprobe-only`** (2026-10-25): the previous published run hard-cut the
  source and this run's one reachability request failed, so nothing else
  was measured; the record keeps the hard code in `cutReasons` and adds
  `reprobe: {passed, kind, previousRun}` (also on a re-probe that passed,
  then fully measured). The app shows a "Re-probed only" chip. A metric that
  could not be measured is `null` at the leaf (`latencyMs.p50/p95`,
  `coverage.found/ratio`, `chapterCompleteness.medianRatio`,
  `imageQuality.medianJpegQuality`, `pagesLoad.ratio`); it adds 0 to the
  score (an unknown `pagesLoad` leaves it unscaled), and an unmeasured
  coverage makes the verdict `pending`. `subsetOf` is `null`
  unless the source is a subset. The UI shows "not measured". The run file
  wraps records as `{generatedAt, runId, referenceSize, sources: [§5...],
  summary: {hostsBlockedHere: [id], keepOnlyViaKeiyoushi: [id],
  notCutOnlyViaKeiyoushi: [{id, name, verdict}]}, meta}`; the summary feeds
  the Suwayomi keep/drop decision (§13).
- **Run meta** (2026-10-25): RTDB `/kartka-e2e/source_health_meta`, a separate
  node (`source_health` stays `{sha1(id): record}`), also `meta` in the run
  file:

  ```json
  {"runId": "2026-W44", "generatedAt": "2026-10-25T12:00:00Z",
   "candidates": 1100, "tested": 585,
   "verdicts": {"keep": 5, "cut": 568, "pending": 12},
   "profile": {"name": "default", "weights": {"...": 0.3}, "keepScore": 0.9,
               "pagesLoadMultiplier": true, "cuts": {"...": false}},
   "skipped": [{"index": "keiyoushi", "reason": "language",
                "count": 900, "names": ["..."]}]}
  ```

  `candidates` = entries in `data/candidates.json`; `tested` = records in
  this run. `skipped` lists every index entry the candidate merge dropped,
  grouped by `index` (`keiyoushi`, `mangayomi`, `sy-backup`) and `reason`
  (`language`, `dart`, `domain-overlap`, `duplicate`; exactly one per entry,
  in that precedence), names sorted. RTDB drops empty lists, so readers must
  tolerate a missing `skipped` or `names`. `profile` is the scoring profile
  the run was judged with (the same shape as above plus `name`: `default`
  exactly when it equals DEFAULT by value, else `custom`); a run without it
  was scored with DEFAULT. Written by the evaluator only (the shared
  account's root rule allows it).
- **Active profile in RTDB** (kuhy's decision, 2026-10-25): the synced setting
  `sourceHealth.scoring` (runtime §16), node
  `/kartka-e2e/settings/sourceHealth~2Escoring` = `{key, value, hlc}`, where
  `value` is the profile as a JSON **string**. The evaluator reads it
  (read-only, via its own `kartka-source-eval` session) at `report`; absent or
  removed means DEFAULT, an unreadable or invalid one falls back to DEFAULT
  with a warning.
- Cadence: uptime probe 4×/day; full metrics weekly; both systemd timers on
  the server host. JSON also written to `tools/source_eval/out/latest.json`.
- **Install / Open** (2026-10-25): every Sources card and detail page has one
  action. A source the app lists, or one with neither `pkg` nor `plugin`
  (native, local, legacy plugins), shows Open (`/browse/source/<id>`). Else
  Install: `pkg` through the `SuwayomiExtensionInstaller` port
  (`updateExtension(input: {id: pkg, patch: {install: true}})` on the
  configured server), `plugin` through `PluginRepoInstaller` (adds the repo,
  then installs `id`). Ports: `lib/source_health/install/install_ports.dart`.
  Failures: snackbar + diagnostics `sources.install`, URLs stripped.
- **Keep auto-install** (2026-10-29, kuhy's request): from the app's first
  screen on, and on every newly published run, `KeepReconciler`
  (`lib/source_health/install/`) installs every `keep` source (under the
  active profile), and every source a library entry uses whatever its
  verdict (2026-10-29), that is not installed, with no prompt: `pkg` on the
  Suwayomi server (one install per package), else `plugin` through the
  plugin manager; at most 2 at a time. "Installed" comes from the
  `InstalledExtensionLister` / `InstalledPluginLister` ports, never the
  live source list (empty while a server is slow). It never uninstalls.
  Each new source is then tested: listed within 60 s and `popular(1)`
  lists a title within 30 s. A failure stays installed, shows "Installed —
  test failed: <reason>" (or "Auto-install failed: <reason>") under the
  card's action, is logged as `sources.autoinstall` (URLs stripped) and is
  re-tested on the next run. The run id (else the newest `probedAt`) and
  the library's source ids are stored per device in kv
  `sourceHealth.autoInstall`, with the flags; a new run id, or a library
  source not seen last time, reconciles again. A side that cannot be read
  leaves them unset, so the next start retries. A library source with no
  record carrying `pkg` / `plugin` (an SY built-in, a removed extension)
  cannot be installed; "Migrate to better sources" lists its entries. The
  Sources tab shows one status line ("Installed 5 sources, 1 failed its
  test") and "Migrate to better sources". Not done in the
  evaluator: it refuses the live server (4567) by design, and the first
  device to reconcile installs on the shared server for all of them.
- **Migrate to better sources** (`lib/migration/better/`, route
  `/more/migrate-better`, also a More tile): every library entry whose
  source is not installed, failed that test, is unreachable / re-probed
  only, cut, or hits a challenge, with the best installed, passing keep
  source (rank order, stopping at the first title match: exact, else a
  fuzzy score >= 0.7 in both directions). Migrate (a row) and a confirmed
  Migrate all write the library backup first, then use `migrateEntry`.
