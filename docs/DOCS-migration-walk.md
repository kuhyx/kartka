# Migration walk: auto pass, descriptions, previews

Additions to the walk described in `DOCS-contracts-source-health.md`
("Migration walk"), from audit 53c9b0fa item 4 (2026-11-21).

## Auto pass (4a)

`WalkAutoPass` (`lib/migration/walk/walk_auto.dart`) is the app bar's
auto-fix icon (spoken "Migrate every strong match"). From the current
entry on, one by one, it waits for the entry's final scores (never the
title-only partials) and migrates the entry to its best candidate when that
score is >= `strongMatch` (0.8, `lib/migration/same_manga.dart`, the bar the
match meter already shows as strong), exactly as a tap on the card does
(backup once, `migrateEntry`). It steps over entries already migrated. It
stops, leaving the walk on that entry, on:

- the first entry whose best candidate is weaker, or has none (manual review);
- a failed backup or migration;
- the end of the walk;
- the stop icon (the migration in flight is written first).

While it runs the app bar shows the auto-fix icon, the count of entries it
migrated and the stop icon; the other actions and the cards are disabled.
Leaving the screen stops it.

Limit: when the entry's own source returns no details, author and
description count as unknown and the best score is 0.775 (0.725 when its
chapter list fails too), so the pass leaves entries on dead sources for
manual review.
