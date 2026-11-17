# Copyright (c) 2026 Krzysztof Rudnicki
"""``perf.slow`` reports: every slow wait of one operation in one record.

The app reports a wait over a second (route + operation + milliseconds);
the signature ignores the time, so all waits of one operation share a ticket
and the record carries the numbers a fix has to beat: how many waits, the
worst, the median and the latest.
"""

from __future__ import annotations

import statistics
from typing import TYPE_CHECKING, TypedDict, cast

if TYPE_CHECKING:
    from kartka_errors.state import Entry, SigRecord

KIND = "perf.slow"
#: Waits kept per signature for the median (older ones only count).
MAX_WAITS = 200


class Detail(TypedDict):
    """What a slow-wait ticket must drive below one second."""

    route: str
    operation: str
    count: int
    max_ms: int
    p50_ms: int
    last_ms: int


def operation_of(entry: Entry | dict[str, object]) -> str:
    """The operation a slow-wait report names (``?`` when it names none)."""
    return str(entry.get("operation") or "?")


def duration_of(entry: Entry) -> int:
    """The reported milliseconds, never negative."""
    ms = entry.get("durationMs")
    return max(ms, 0) if isinstance(ms, int) and not isinstance(ms, bool) else 0


def add_wait(rec: SigRecord, device: str, entry_id: str, entry: Entry) -> None:
    """Count ``entry`` as a wait; a repeat report of one wait only updates it.

    A wait still going at 5 s is reported, then reported again when it ends
    under the same ``waitId``: that is one wait, with the final duration.
    """
    key = f"{device}/{entry.get('waitId') or entry_id}"
    ms, at = duration_of(entry), entry["at"]
    for wait in rec["waits"]:
        if wait["id"] == key:
            wait["ms"], wait["at"] = max(wait["ms"], ms), max(wait["at"], at)
            break
    else:
        rec["count"] += 1
        rec["waits"].append({"id": key, "ms": ms, "at": at})
        del rec["waits"][:-MAX_WAITS]
    rec["detail"] = _detail(rec, ms)


def _detail(rec: SigRecord, ms: int) -> dict[str, object]:
    waits = rec["waits"]
    old = cast("dict[str, object]", rec.get("detail") or {})
    last = max(waits, key=lambda w: w["at"])
    detail: Detail = {
        "route": rec["sample"].get("route", "?"),
        "operation": operation_of(rec["sample"]),
        "count": rec["count"],
        "max_ms": max(int(cast("int", old.get("max_ms", 0))), ms),
        "p50_ms": int(statistics.median(w["ms"] for w in waits)),
        "last_ms": last["ms"],
    }
    return cast("dict[str, object]", detail)
