# Source evaluator (`tools/source_eval/`)

Decides, by measurement, which manga sources Kartka keeps. Output is the
contract §5 record ([`DOCS-contracts-source-health.md`](DOCS-contracts-source-health.md))
per source, ranked, plus a run `meta` block, written to
`tools/source_eval/out/latest.json` and, with `--publish`, to RTDB
`/kartka/source_health/<sha1(sourceId)>` and `/kartka/source_health_meta`.

## Commands

All from `tools/source_eval/` (Python 3.15, uv; deps exact-pinned, `uv.lock`
committed):

```bash
uv run pytest                       # 100 % line+branch coverage gate
uv run ruff check src tests && uv run ruff format --check src tests
uv run mypy --strict src tests

uv run source-eval candidates --budget 50      # data/candidates{,_skipped}.json
uv run source-eval reference --budget 50       # data/reference.json (resumable)
uv run source-eval ramp start --run R [--sample N]   # this run's sample (ramp)
uv run source-eval init-run --run R --sample 30 --completeness 10 --images 3 --pages 2
uv run source-eval init-run --run R --ramp --reprobe # weekly: ramp + re-probes
uv run source-eval enrich --run R --budget 50  # MangaUpdates chapter counts
uv run source-eval probe [--ids ...|--installed] --fresh 10800 --budget 50
uv run source-eval run --run R [--ids <id>] --workers 128 --inflight 64 --budget 50
uv run source-eval report --run R [--out F] [--publish] [--weights active|default] --budget 50
uv run source-eval ramp finish --run R         # records the run's wall time
```

**Batches** (kuhy, 2026-10-25): every invocation finishes in < 60 s.
`--budget S` (default 55, so manual calls too) is a hard wall-clock limit
counted from process start, in-flight
requests included: a request starts only when its timeout fits in what is
left (minus 1 s grace), shortened to fit when needed (but at least 5 s, or
its whole timeout); a shortened timeout that runs out is the budget's stop,
never the source's failure, and the step is redone next call. A request's
own full timeout (20 s for Suwayomi; W43 saw 0.07 % slower responses) is a
failure as before. Every request runs under a total wall-clock cap
(`BoundedTransport`), not just `requests`' per-socket timeout. Exit 10 =
call again. `systemd/batch.sh` loops a step until exit 0 (`--budget 50`,
`timeout 58` as a backstop that only warns, 2000 batches max per step);
`weekly.sh`, `probe.sh` and `pilot.sh` are such loops. `report --publish`
writes records in chunks of 200 (by RTDB key), then the meta, remembering
each finished write in `runs/<run>/publish.json`. The hosts-file lookup
after a failed probe is capped at 3 s (a dead domain's `getaddrinfo`
stalled 40 s here) and at what is left of the budget.

**Throughput**: `run` groups sources by host into lanes (`--workers`, one
host per lane, worked serially) with at most `--inflight` requests in the
air (the eval server queues more itself, which would inflate the latency it
reports). The 2 s per-host spacing of request *starts* is unchanged; the
in-flight slot is taken under the host's lock, right before the claim.

**Ramp** (`ramp.json` in the state dir): the weekly sample is 50 titles more
than the previous run's when that run took <= 2 h (first `ramp start` to
`ramp finish`, after the publish; a resumed run counts the whole span),
50 fewer when it took longer, within [200, 500]. `KARTKA_EVAL_SAMPLE`
overrides it (and is ramped from next week).

**Re-probe**: a finished `report --publish` writes `hard_cut.json` (ids
whose `cutReasons` hold `unreachable` or `blocking>=0.50`); `init-run
--reprobe` freezes them into the next run's manifest. Each gets one
`popular` request first: passed (an answer, or only a `webview` need) →
measured as usual; failed → nothing else this run, record `reprobe:
{passed, kind, previousRun}`, `flags: ["reprobe-only"]`, the hard cut kept
(`unreachable`, or `blocking>=0.50` for a challenge).

`--suwayomi-url` (or `KARTKA_SUWAYOMI_URL`, default the eval instance
`http://127.0.0.1:4590`; the live 4567 is refused);
basic auth from `KARTKA_SUWAYOMI_USER/PASS` or the deploy env file's
`SUWAYOMI_USER/SUWAYOMI_PASSWORD`. State: `$XDG_STATE_HOME/kartka-source-eval`
(runs, uptime history, per-host last-request times); cache:
`$XDG_CACHE_HOME/kartka-source-eval`.

Timers (`systemd/`): probe 4x/day (`probe.sh`), full run weekly via
`systemd/weekly.sh` (ISO-week run id, ramped sample, publish).

## Pipeline

1. **Candidates** (`candidates/`): every `en`/`ja`/`all` source in
   Keiyoushi's `index.pb` (gzipped protobuf, decoded schema-less by
   `protowire.py`; MangaDex en decodes to `2499283573021220255`, as in the
   contract), native MangaDex, Mangayomi **JS** sources on domains Keiyoushi
   does not cover (`plugin:mangayomi-<id>`), and `data/legacy_sources.json`
   (`plugin:legacy-<slug>`, see below). kuhy's installed set is flagged.
   Every dropped index entry goes to `data/candidates_skipped.json` with one
   reason (`language` > `dart` > `domain-overlap` > `duplicate`), grouped per
   index; it becomes the run meta's `skipped`.
2. **Reference** (`reference/`): AniList top 500 manga by popularity
   (`format_not: NOVEL`) with every alt title; plus `data/sy_titles.json` if
   present (list of strings or `{title}`; gitignored), matched to AniList.
   Missing chapter counts (ongoing series) come from MangaUpdates. Each
   title stores AniList's native title (`nativeTitle`: `null` = not fetched,
   `""` = none); titles stored before the field existed are backfilled by the
   next `reference` call (batched `id_in`, 50 per request).
3. **Run** (`evaluate.py`): one deterministic stratified sample per run, the
   same for every source. Per source: install/prepare; search each title
   (main title, then first alt; a `ja` source: native title, then the first
   other title) and fuzzy-match (rapidfuzz ratio ≥ 0.90 on normalised titles,
   any alt title, plus the native one for `ja`); chapter lists for the first N found;
   page images for the first M (median chapter, skip page 1, P pages).
   Every step checkpoints to disk atomically. A source stops early after 3
   challenged requests (`blocking`) or 5 failed first searches (`unreachable`).
4. **Report** (`metrics.py`, `score.py`, `report.py`).

## Backends (one `Backend` Protocol)

- **MangaDex API**: `/manga?title=` (English-available), `/manga/{id}/feed`
  (English, `includeExternalUrl=0`, distinct chapter numbers), `/at-home`.
- **Suwayomi GraphQL**: `fetchSourceManga` (SEARCH/POPULAR),
  `fetchMangaAndChapters` (`fetchChapters: true`), `fetchChapterPages`, page
  bytes from `/api/v1/...`. Extensions are installed on demand
  (`fetchExtensions` + `updateExtension`). Requests are paced by the
  **source's** host, not the server's.
- **Kartka JS plugins**: stub (`backends/plugin.py`). Plugin candidates get
  uptime probes only and stay `pending`.

## Politeness (`polite.py`)

≤ 1 request / 2 s per host, last-request times persisted across processes;
honest User-Agent `kartka-source-eval/0.1 (+https://github.com/kuhyx/kartka)`;
429 honours `Retry-After` (cap 20 s, 2 retries); JSON responses cached 6 days.
Cache hits are never observed, so they cannot flatten latency or uptime.
Only the eval server's own extension lookup (its local database, no
third-party host behind it) skips the gate. Challenges are detected, never solved: the Suwayomi server must run with KCEF
and FlareSolverr off (the local dev server and the live deploy both do).

## Metric definitions and decisions

- **uptime**: one uncached probe per source 4x/day, through the backend
  ("popular, page 1"), because a front page can be challenged while the API
  works (mangadot.net: Cloudflare 403 on `/`, API fine). Plugin candidates
  fall back to a front-page GET. `final` once probes span 7 days − 6 h.
- **hosts-blocked**: a host this machine's hosts-file blocklist sinks
  (0.0.0.0) is recorded as `hosts-blocked`, excluded from every metric and
  listed in `summary.hostsBlockedHere`. The evaluator never routes around it.
- **latency** p50/p95 (nearest rank) over live responses: uptime window +
  the run's requests.
- **blocking**: challenged / all observations. Kinds: `cloudflare`, `captcha`,
  `403`, `429`, plus **`webview`** = the extension needs a browser engine to
  read the site (Suwayomi "CEF is disabled"). Recorded in `kinds` and
  `challengeRate` but **flagged, not cut**: the record gets
  `flags: ["needs-browser-engine"]`, and `webview` challenges neither cut the
  source nor abort its measurement. The evaluator still never runs a browser.
- **coverage**: found / sample size; `referenceSize` is the run's sample size
  (30 in the sample run, 200 weekly), not the full 500, to stay honest.
- **chapterCompleteness**: distinct chapter numbers / AniList (else
  MangaUpdates `latest_chapter`) count, capped at 1, median over sampled
  titles with a known count.
- **imageQuality**: median width; JPEG quality estimated by inverting IJG
  scaling of the luminance quant table (sum-based, order-independent; a
  hypothesis test round-trips Pillow `quality=q`). Median over JPEGs only, so
  `null` for WebP/PNG-only sources.
- **Unmeasured metrics are `null`, never 0**: a source no backend can read
  is never judged on coverage; its verdict stays `pending`. It scores 0 for that term.
- **pagesLoad**: loaded / attempted chapters of the image step, read from the
  stored per-chapter outcomes (`state.images`: an `error` or an empty page
  list is a failure), so any existing run state re-reports without
  re-measuring. `null` when no chapter was attempted. It only scales the
  score (no cut reason): a ratio of 0 scores 0, `null` leaves it unscaled.
- **langScope**: `en+ja` unless the source is `all` (then `unrestricted`).
  Restricting an `all` Suwayomi extension would need per-extension language
  preferences (keys differ per extension and are unverified here); MangaDex
  native is restricted by `translatedLanguage=en`.
- **score**: the §5 formula under the active scoring profile
  (`source_eval/profile.py`; weights normalised, pages-load multiplier
  optional). Under DEFAULT it is the historic one (the §5 example's printed
  0.81 is wrong; its own inputs give 0.852, pinned by a test). Rounded to 3
  places. Every record also carries `defaultScore` (DEFAULT profile).
- **subset**: ≥ 90 % of found titles also found by a higher-ranked, not-cut
  source whose median width is ≥ (unknown width of the lower source counts as
  ≤; unknown width of the higher one never qualifies). Same-host pairs are
  compared too (native vs Suwayomi MangaDex): the lower one is redundant.
  Ties rank native > suwayomi > plugin.
- **verdict**: an enabled cut switch whose reason applies → `cut`; else
  ≥ `keepScore` → `keep`; `pending` only while nothing was measured
  (coverage ratio `null`); else `cut`. DEFAULT enables no switch, so there the
  score alone decides (`KEEP_SCORE` 0.90). The cut reasons (`uptime<0.95`,
  `blocking`, `coverage<0.60`, `subset`) are always computed and published in
  `cutReasons`.
- **scoring profile**: `report` reads the app's active profile from RTDB
  `/kartka/settings/sourceHealth~2Escoring` (read-only GET with the
  `kartka-source-eval` session, even without `--publish`) and scores,
  ranks and publishes with it. `--weights default` skips the read and forces
  DEFAULT. Node absent or removed = DEFAULT; an unreadable or invalid profile
  (or no sign-in) falls back to DEFAULT and prints a `warning:` line.
  `report` prints `profile: default|custom`.
- **meta**: `{runId, generatedAt, candidates, tested, verdicts, skipped,
  profile}` (contract §5 "Run meta"); `--publish` PATCHes it to
  `/kartka/source_health_meta` after the records. `profile` is
  `{name: default|custom, weights, pagesLoadMultiplier, keepScore, cuts}`.
- **availability** (additive): `native` (Kartka Dart source; today
  mangadex.org), `mangayomiJs` (a Mangayomi JS source on the same base
  domain), `keiyoushi`. `summary.keepOnlyViaKeiyoushi` lists `keep` sources
  that only Suwayomi can read; `summary.notCutOnlyViaKeiyoushi` adds pending.

## Legacy sources in kuhy's SY backup

Not in Keiyoushi or Suwayomi; identified from source names stored in older
backups (`backupSources`) and entry URLs. All are `plugin:legacy-*`:

| backup ids | site | entries | status here |
|---|---|---|---|
| 3091964041986261235 | MangaDex (Revived): old MangaDex id, `/manga/<uuid>` | 269 | covered by `mangadex` |
| 4531…129, 7890…109, 4936…860, 4659…292 | Bato.to (old `all.batoto`) | 131 | hosts-blocked here |
| 2292947733994124621 | MangaPark (`all.mangapark`; Mangayomi Dart only) | 9 | HTTP 521 |
| 8758…879, 6901…713 | Hitomi | 3 | hosts-blocked |
| 7309872737163460316 | NHentai | 6 | hosts-blocked |
| 6901 / 6902 | E-Hentai / ExHentai (SY built-ins) | 97 / 109 | hosts-blocked |

## Local development server

Suwayomi-Server v2.4.2366 jar (sha256-checked) in
`~/.local/share/kartka-source-eval/`, rootDir `.../suwayomi`, `127.0.0.1:4590`,
KCEF/FlareSolverr/tray/WebUI off, run as transient user unit
`kartka-suwayomi-eval` (`systemctl --user stop kartka-suwayomi-eval`):
`-Xmx2g`, `CPUQuota=100%`, `MemoryMax=3G`. `maxSourcesInParallel` stays 6:
in the server jar only the library updater and the downloader read it
(range 1..20); the GraphQL browse/search/chapter path has no such limit.
