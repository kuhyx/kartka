# Copyright (c) 2026 Krzysztof Rudnicki
"""Permanent rejects (kuhy, 2026-11-20): a source measured at <= 0.65 is gone.

``rejected.json`` in the state dir maps each rejected id to ``{score, runId,
rejectedAt}``. Code only ever adds to it; undo = delete the id from the file
by hand. A rejected source is never selected for ``run`` or ``probe`` again,
never re-probed, left out of the report, and ``report --publish`` deletes its
RTDB record. The file is written only by a finished publish, so a dry-run
``report`` changes no state.
"""

from __future__ import annotations

import datetime as dt
from typing import TYPE_CHECKING, cast

from source_eval.fsio import read_json, write_json_atomic
from source_eval.metrics import FLAG_REPROBE_ONLY
from source_eval.profile import DEFAULT
from source_eval.score import score

if TYPE_CHECKING:
    from pathlib import Path

    from source_eval.models import Candidate
    from source_eval.profile import Profile
    from source_eval.score import Record

#: A measured own score at or below this rejects the source for good.
REJECT_SCORE = 0.65
#: Built-in Kartka sources: they cannot be removed, so never rejected.
_NATIVE = "native"
REJECTED_FILE = "rejected.json"

Entries = dict[str, dict[str, object]]


def load(state_dir: Path) -> Entries:
    """The rejected ids and why (empty without a file)."""
    return cast("Entries", read_json(state_dir / REJECTED_FILE, {}))


def without(cands: list[Candidate], state_dir: Path) -> list[Candidate]:
    """``cands`` minus every rejected id."""
    gone = load(state_dir)
    return [c for c in cands if c.id not in gone]


def own_score(record: Record, profile: Profile = DEFAULT) -> float:
    """The source's own score under ``profile``: without the subset penalty."""
    return score({**record, "subsetOf": None}, profile)


def eligible(record: Record, profile: Profile = DEFAULT) -> bool:
    """A measured cut whose own score is at most the bar; never a native one.

    Measured: coverage known, not pending, not a re-probe only (kuhy,
    2026-11-21). A source pushed under the bar only by the subset penalty
    stays judged; a hard cut is rejected too. A ``keep`` never is, so a
    custom keep bar below 0.65 cannot remove a kept source.
    """
    coverage = cast("dict[str, object]", record.get("coverage") or {})
    flags = cast("list[str]", record.get("flags") or [])
    return (
        record["verdict"] == "cut"
        and record.get("origin") != _NATIVE
        and coverage.get("ratio") is not None
        and FLAG_REPROBE_ONLY not in flags
        and own_score(record, profile) <= REJECT_SCORE
    )


def apply(
    report: dict[str, object],
    known: Entries,
    run_id: str,
    now: float,
    profile: Profile = DEFAULT,
) -> Entries:
    """Drop rejected records from ``report``; returns every rejected id.

    New rejects (eligible, not ``known``) join ``known``, which is never
    changed. The rest keep their order and are ranked 1..n again; the meta's
    ``tested`` and ``verdicts`` count them, ``rejected`` counts the merged
    set and ``rejectedIds`` lists it sorted (also ``report["rejected"]``).
    An entry's ``score`` is the own score.
    """
    at = dt.datetime.fromtimestamp(now, dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    sources = cast("list[Record]", report["sources"])
    merged = dict(known)
    for record in sources:
        if str(record["id"]) not in merged and eligible(record, profile):
            merged[str(record["id"])] = {
                "score": own_score(record, profile),
                "runId": run_id,
                "rejectedAt": at,
            }
    kept = [r for r in sources if str(r["id"]) not in merged]
    verdicts = {"keep": 0, "cut": 0, "pending": 0}
    for position, record in enumerate(kept, start=1):
        record["rank"] = position
        verdicts[str(record["verdict"])] += 1
    meta = cast("dict[str, object]", report["meta"])
    meta.update(tested=len(kept), verdicts=verdicts, rejected=len(merged))
    meta["rejectedIds"] = sorted(merged)
    report["sources"], report["rejected"] = kept, merged
    return merged


def save(state_dir: Path, merged: Entries) -> None:
    """Add ``merged`` to the file; an id already there keeps its entry."""
    write_json_atomic(state_dir / REJECTED_FILE, {**merged, **load(state_dir)})
