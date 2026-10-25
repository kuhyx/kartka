# Copyright (c) 2026 Krzysztof Rudnicki
"""Cross-check with the Dart app: both suites read ``scoring_profile.json``."""

from __future__ import annotations

import copy
from typing import Any, cast

import pytest

from source_eval import profile as profile_mod
from source_eval.profile import DEFAULT, Profile, parse_profile
from source_eval.score import (
    COMPLETE_CHAPTERS,
    COVERAGE_MIN,
    HARD_CHALLENGE_RATE,
    LEGACY_COVERAGE_SHARE,
    P95_ZERO,
    SUBSET_MIN,
    SUBSET_PENALTY,
    UPTIME_MIN,
    WIDTH_FULL,
    Record,
    rank,
)
from tests.fakes import fixture_json

SHARED = cast("dict[str, Any]", fixture_json("scoring_profile.json"))


def named(name: str) -> Profile:
    """A profile of the fixture by name (``default`` is the DEFAULT)."""
    if name == "default":
        return DEFAULT
    parsed = parse_profile(SHARED["profiles"][name])
    assert parsed is not None
    return parsed


def test_default_profile_is_the_shared_default() -> None:
    assert DEFAULT.to_json() == SHARED["default"]
    assert parse_profile(SHARED["default"]) == DEFAULT


def test_scale_and_thresholds_are_shared() -> None:
    assert SHARED["scale"] == {"fullWidthPx": WIDTH_FULL, "worstP95Ms": P95_ZERO}
    assert SHARED["thresholds"] == {
        "minUptime": UPTIME_MIN,
        "minCoverage": COVERAGE_MIN,
        "subsetOverlap": SUBSET_MIN,
        "subsetPenalty": SUBSET_PENALTY,
        "hardChallengeRate": HARD_CHALLENGE_RATE,
        "completeChapterRatio": COMPLETE_CHAPTERS,
        "legacyCoverageShare": LEGACY_COVERAGE_SHARE,
    }


def test_setting_key_and_node_are_shared() -> None:
    assert SHARED["settingKey"] == profile_mod.SETTING_KEY
    assert SHARED["settingNode"] == profile_mod.SETTING_NODE


@pytest.mark.parametrize("case", SHARED["parse"], ids=lambda c: c["name"])
def test_parse_cases(case: dict[str, Any]) -> None:
    expected = None if case["profile"] is None else named(case["profile"])
    assert parse_profile(case["input"]) == expected


@pytest.mark.parametrize("name", list(SHARED["expect"]))
def test_golden_judgements(name: str) -> None:
    expected = SHARED["expect"][name]
    records = cast("list[Record]", copy.deepcopy(SHARED["records"]))
    for record in records:
        record.pop("cutReasons")  # the evaluator derives these itself
        record.pop("subsetOf")
    found = {k: set(v) for k, v in SHARED["found"].items()}
    ranked = rank(records, found, named(name))
    assert [r["id"] for r in ranked] == expected["order"]
    assert [r["rank"] for r in ranked] == list(range(1, len(ranked) + 1))
    published = {r["id"]: r for r in SHARED["records"]}
    for record in ranked:
        rid = str(record["id"])
        assert [record["score"], record["verdict"]] == expected["judged"][rid]
        assert record["defaultScore"] == SHARED["expect"]["default"]["judged"][rid][0]
        assert record["cutReasons"] == published[rid]["cutReasons"]
        assert record["subsetOf"] == published[rid]["subsetOf"]
