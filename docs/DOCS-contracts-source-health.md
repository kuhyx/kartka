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
  "score": 0.852, "rank": 3,
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
- **Cut reasons (explanatory only)**: `uptime<0.95` (ratio < 0.95, only once
  `final`), `blocking` (challengeRate > 0 from any kind other than `webview`),
  `coverage<0.60`, `subset`. They are computed and published in `cutReasons`
  to explain a low score and the UI shows them, but they **never decide the
  verdict**. Page loading has no reason of its own: it only lowers the score.
- **Verdict** (score only, 2026-10-25): score ≥ 0.90 (`KEEP_SCORE`) → `keep`;
  `pending` only while the source is not yet measured (`coverage.ratio` is
  `null`); otherwise `cut`. Uptime still accruing does not force `pending`
  (uptime is already a score component). A `keep` may carry `cutReasons`
  (warnings); a `cut` may carry none.
- **Score**: (0.30 coverage + 0.20 completeness + 0.20 uptime + 0.15 image
  quality (width/1400 capped) + 0.15 latency (1 − p95/5000 capped at 0)) ×
  `pagesLoad.ratio` when that is not `null`, so a source whose pages never
  load scores 0 and is cut by its score alone.
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
  engine" chip on the Sources row, the detail page and the Browse badge. A metric that
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
- **Run meta** (2026-10-25): RTDB `/kartka/source_health_meta`, a separate
  node (`source_health` stays `{sha1(id): record}`), also `meta` in the run
  file:

  ```json
  {"runId": "2026-W44", "generatedAt": "2026-10-25T12:00:00Z",
   "candidates": 1100, "tested": 585,
   "verdicts": {"keep": 5, "cut": 568, "pending": 12},
   "skipped": [{"index": "keiyoushi", "reason": "language",
                "count": 900, "names": ["..."]}]}
  ```

  `candidates` = entries in `data/candidates.json`; `tested` = records in
  this run. `skipped` lists every index entry the candidate merge dropped,
  grouped by `index` (`keiyoushi`, `mangayomi`, `sy-backup`) and `reason`
  (`language`, `dart`, `domain-overlap`, `duplicate`; exactly one per entry,
  in that precedence), names sorted. RTDB drops empty lists, so readers must
  tolerate a missing `skipped` or `names`. Written by the evaluator only
  (the shared account's root rule allows it).
- Cadence: uptime probe 4×/day; full metrics weekly; both systemd timers on
  the server host. JSON also written to `tools/source_eval/out/latest.json`.
