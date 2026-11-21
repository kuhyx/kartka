# Audit of todo note 53c9b0fa (2026-11-21)

The todo app marked note 53c9b0fa ("kartka when rating sources ignore manhwas
...") done on 2026-11-21 07:55. The evidence it carries is a different
note's (fe572224: reader speed, error reports). This file checks each of the
note's six items against the code and tests, lists the gaps, and records how
each gap was closed in the same run.

## Items

| # | Item | State before this run | Gap |
|---|------|-----------------------|-----|
| 1 | Rate sources by manga only, ignoring manhwa and manhua | Present: only `JP` titles count (`tools/source_eval/src/source_eval/country.py`, `app.py`, `publishing.py`) | None |
| 2 | Keep at >= 0.85; reject at <= 0.65 for good, never re-judge | Partial: bars and the permanent reject list exist (`profile.py`, `rejected.py`) and the app treats rejected ids as cut | 2a: a rejected extension stayed installed in the app. 2b: built-in sources are exempt, which the docs did not say |
| 3 | Filter by content type | Present: a 3-state toggle (1 / 2 / infinity) | Q2 caption; superseded by the checkbox sheet (Manga / Manhwa / Manhua) of part 0a69e95b-1 |
| 4 | Migration better than Tachiyomi | Partial: walk, 5 sources x 5 alternatives, cover, chapter count, newest date and the match meter exist (`lib/migration/walk/`) | 4a: no automatic pass, every entry needed a tap. 4b: the description was used for scoring but never shown. 4c: no page previews of the target |
| 5 | Auto-shelve after 18 months: finished if all read, else completed/abandoned | Present (`lib/library/state/auto_shelver.dart`) | 5a: an entry with no stored chapter list was never judged. 5b: a moved entry kept its other categories |
| 6 | Auto-merge identical manga into the best source | Present (`lib/migration/dedupe/`) | Same as 5a: entries with no stored chapter list were skipped |

## Gaps closed

Each gap's fix commit and test are listed in the commit log under the
`Audit-53c9b0fa:` trailer; `git log --grep Audit-53c9b0fa` lists them.

## Why the note closed early

Fixed in todoImplementer:
- Part `53c9b0fa-0` joined repo-task card bcf6a474-0 after its plan was
  written.
- The live check still covered only the first note's criteria (C1-C10).
- The session ticked every part, and ship closed every ticked part with the
  one card-wide evidence string. Nothing checked that a criterion named
  each part.

Ship now refuses a card whose ticked part has no passed criterion naming
it. Each closed note carries only its own rows.
