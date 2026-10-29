# Copyright (c) 2026 Krzysztof Rudnicki
"""Rank order (contract §5): rank tier first, then score, origin and id.

A source that needs a browser engine (the ``needs-browser-engine`` flag) or
hits a challenge (any ``blocking`` cut reason) still works, so neither cuts
it under DEFAULT, but each ranks it below every source without it: the tier
is how many of the two apply, 0..2 (decision 2026-10-29). Score and verdict
are untouched, so a usable KCEF source stays ``keep``.
"""

from __future__ import annotations

from typing import cast

from source_eval.challenge import FLAG_BROWSER_ENGINE

_ORIGIN_ORDER = {"native": 0, "suwayomi": 1, "plugin": 2}
#: Prefix of the challenge cut reasons, ``blocking`` and ``blocking>=0.50``.
_BLOCKING = "blocking"


def rank_tier(record: dict[str, object]) -> int:
    """0 for neither, 1 for a browser engine or a challenge, 2 for both."""
    flags = cast("list[str]", record.get("flags") or [])
    codes = cast("list[str]", record.get("cutReasons") or [])
    browser = FLAG_BROWSER_ENGINE in flags
    challenged = any(code.startswith(_BLOCKING) for code in codes)
    return int(browser) + int(challenged)


def ordered(records: list[dict[str, object]]) -> list[dict[str, object]]:
    """``records`` best-first: tier, then score, origin and id."""
    return sorted(
        records,
        key=lambda r: (
            rank_tier(r),
            -cast("float", r["score"]),
            _ORIGIN_ORDER.get(str(r["origin"]), 9),
            str(r["id"]),
        ),
    )
