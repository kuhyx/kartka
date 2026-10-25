# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import dataclasses
import math

from hypothesis import given
from hypothesis import strategies as st

from source_eval.profile import DEFAULT, Cuts, Profile, Weights, parse_profile
from source_eval.score import Record, applicable_cuts, score, verdict
from tests.test_scoring import record


def test_default_is_the_evaluators_historic_weights() -> None:
    w = DEFAULT.weights
    assert (w.coverage, w.chapter_completeness, w.uptime) == (0.30, 0.20, 0.20)
    assert (w.image_quality, w.speed) == (0.15, 0.15)
    assert DEFAULT.keep_score == 0.90
    assert DEFAULT.pages_load_multiplier
    assert DEFAULT.cuts.enabled() == frozenset()
    assert DEFAULT.name == "default"


def test_name_is_custom_exactly_when_it_differs_by_value() -> None:
    same = parse_profile(DEFAULT.to_json())
    assert same == DEFAULT
    assert same is not None
    assert same.name == "default"
    tweaked = dataclasses.replace(DEFAULT, keep_score=0.91)
    assert tweaked.name == "custom"
    assert tweaked.to_json()["keepScore"] == 0.91


def test_weights_are_normalised_to_sum_one() -> None:
    weights = Weights(1, 0.5, 0.5, 0, 0)
    assert weights.normalised() == (0.5, 0.25, 0.25, 0.0, 0.0)
    assert math.isclose(sum(DEFAULT.weights.normalised()), 1.0)


def test_cuts_enabled_names_match_the_wire() -> None:
    cuts = Cuts(subset=True, needs_browser_engine=True, pages_never_load=True)
    assert cuts.enabled() == {"subset", "needsBrowserEngine", "pagesNeverLoad"}


def test_default_score_unchanged_by_normalisation() -> None:
    example = record("x", coverage=0.788, complete=0.97, up=0.964, width=1100, p95=1300)
    assert score(example, DEFAULT) == 0.852


def test_pages_multiplier_can_be_switched_off() -> None:
    r: Record = {**record("x"), "pagesLoad": {"ratio": 0.5, "sampled": 4}}
    off = dataclasses.replace(DEFAULT, pages_load_multiplier=False)
    assert score(r, off) == score(record("x"))
    assert score(r) == round(score(record("x")) * 0.5, 3)
    assert score(r, DEFAULT) < score(r, off)


def test_applicable_cuts_cover_every_reason() -> None:
    r: Record = {
        **record("x", challenge=0.2, coverage=0.1),
        "cutReasons": ["blocking", "coverage<0.60", "uptime<0.95", "subset"],
        "flags": ["needs-browser-engine"],
        "pagesLoad": {"ratio": 0, "sampled": 3},
    }
    assert applicable_cuts(r) == {
        "blocking",
        "coverage",
        "uptime",
        "subset",
        "needsBrowserEngine",
        "pagesNeverLoad",
    }
    assert applicable_cuts(record("x")) == set()
    unmeasured: Record = {**record("x"), "pagesLoad": {"ratio": None, "sampled": 0}}
    assert applicable_cuts(unmeasured) == set()


def test_verdict_cut_switch_beats_a_high_score() -> None:
    r: Record = {**record("x", complete=1, p95=0), "cutReasons": ["subset"]}
    r["score"] = 0.95
    assert verdict(r, DEFAULT) == "keep"
    switched = dataclasses.replace(DEFAULT, cuts=Cuts(subset=True))
    assert verdict(r, switched) == "cut"
    other = dataclasses.replace(DEFAULT, cuts=Cuts(blocking=True))
    assert verdict(r, other) == "keep"


@given(st.lists(st.floats(0, 1), min_size=5, max_size=5), st.booleans())
def test_any_valid_profile_scores_in_unit_interval(
    values: list[float], multiply: bool
) -> None:
    if sum(values) == 0:
        return
    p = Profile(Weights(*values), multiply, 0.9, Cuts())
    r: Record = {**record("x"), "pagesLoad": {"ratio": 0.7, "sampled": 5}}
    assert 0.0 <= score(r, p) <= 1.0
