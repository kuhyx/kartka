# Copyright (c) 2026 Krzysztof Rudnicki
"""Rank tiers: a browser engine or a challenge ranks low, both lowest."""

from __future__ import annotations

from source_eval.tier import ordered, rank_tier
lazy from source_eval.score import Record


def _rec(
    rid: str,
    score: float,
    *,
    flags: list[str] | None = None,
    reasons: list[str] | None = None,
    origin: str = "suwayomi",
) -> Record:
    return {
        "id": rid,
        "origin": origin,
        "score": score,
        "flags": flags or [],
        "cutReasons": reasons or [],
    }


def test_tier_counts_browser_engine_and_challenge() -> None:
    assert rank_tier(_rec("a", 1)) == 0
    assert rank_tier({"id": "bare", "origin": "native", "score": 1}) == 0
    assert rank_tier(_rec("b", 1, flags=["needs-browser-engine"])) == 1
    assert rank_tier(_rec("c", 1, reasons=["blocking"])) == 1
    assert rank_tier(_rec("d", 1, reasons=["blocking>=0.50"])) == 1
    both = _rec("e", 1, flags=["needs-browser-engine"], reasons=["blocking"])
    assert rank_tier(both) == 2


def test_other_reasons_and_flags_do_not_tier() -> None:
    other = _rec("a", 1, flags=["reprobe-only"], reasons=["uptime<0.95", "subset"])
    assert rank_tier(other) == 0


def test_tier_sorts_before_score_then_origin_then_id() -> None:
    records = [
        _rec("both", 1, flags=["needs-browser-engine"], reasons=["blocking"]),
        _rec("kcef", 1, flags=["needs-browser-engine"], origin="native"),
        _rec("cf", 0.99, reasons=["blocking"]),
        _rec("weak", 0.1, origin="plugin"),
        _rec("good", 0.9),
        _rec("good-native", 0.9, origin="native"),
    ]
    assert [r["id"] for r in ordered(records)] == [
        "good-native",
        "good",
        "weak",
        "kcef",
        "cf",
        "both",
    ]
