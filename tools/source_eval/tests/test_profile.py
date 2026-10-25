# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import dataclasses
import math

from hypothesis import given
from hypothesis import strategies as st

from source_eval.profile import DEFAULT, Cuts, Profile, Weights, parse_profile
from source_eval.score import Record, applicable_cuts, score, verdict
from tests.test_scoring import record


def test_default_merges_the_historic_coverage_weights() -> None:
    w = DEFAULT.weights
    assert (w.complete_coverage, w.uptime) == (0.30 + 0.20, 0.20)
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
    weights = Weights(1, 0.5, 0.5, 0)
    assert weights.normalised() == (0.5, 0.25, 0.25, 0.0)
    assert math.isclose(sum(DEFAULT.weights.normalised()), 1.0)


def test_cuts_enabled_names_match_the_wire() -> None:
    cuts = Cuts(coverage=True, needs_browser_engine=True, pages_never_load=True)
    assert cuts.enabled() == {"coverage", "needsBrowserEngine", "pagesNeverLoad"}


def test_a_legacy_record_scores_its_old_coverage_split() -> None:
    """No ``completeRatio``: the old .30 coverage / .20 completeness split.

    0.5 * (0.6 * .788 + 0.4 * .97) + 0.2 * .964 + 0.15 * 1 (1100 >= 1067 px)
    + 0.15 * (1 - 1300 / 5000) = 0.8842.
    """
    example = record("x", coverage=0.788, complete=0.97, up=0.964, width=1100, p95=1300)
    assert score(example, DEFAULT) == 0.884


def test_pages_multiplier_can_be_switched_off() -> None:
    r: Record = {**record("x"), "pagesLoad": {"ratio": 0.5, "sampled": 4}}
    off = dataclasses.replace(DEFAULT, pages_load_multiplier=False)
    assert score(r, off) == score(record("x"))
    assert score(r) == round(score(record("x")) * 0.5, 3)
    assert score(r, DEFAULT) < score(r, off)


def test_applicable_cuts_cover_every_reason() -> None:
    r: Record = {
        **record("x", challenge=0.2, coverage=0.1),
        "cutReasons": ["blocking>=0.50", "coverage<0.60", "uptime<0.95", "subset"],
        "flags": ["needs-browser-engine"],
        "pagesLoad": {"ratio": 0, "sampled": 3},
    }
    assert applicable_cuts(r) == {
        "blocking",
        "coverage",
        "uptime",
        "needsBrowserEngine",
        "pagesNeverLoad",
    }
    assert applicable_cuts(record("x")) == set()
    unmeasured: Record = {**record("x"), "pagesLoad": {"ratio": None, "sampled": 0}}
    assert applicable_cuts(unmeasured) == set()


def test_verdict_cut_switch_beats_a_high_score() -> None:
    r: Record = {**record("x", complete=1, p95=0), "cutReasons": ["coverage<0.60"]}
    r["score"] = 0.95
    assert verdict(r, DEFAULT) == "keep"
    switched = dataclasses.replace(DEFAULT, cuts=Cuts(coverage=True))
    assert verdict(r, switched) == "cut"
    other = dataclasses.replace(DEFAULT, cuts=Cuts(blocking=True))
    assert verdict(r, other) == "keep"


def test_the_hard_filter_beats_any_score_and_profile() -> None:
    for code in ("unreachable", "blocking>=0.50"):
        r: Record = {**record("x"), "cutReasons": [code], "score": 1.0}
        assert verdict(r, DEFAULT) == "cut"
    subset: Record = {**record("x"), "cutReasons": ["subset"], "score": 0.95}
    assert verdict(subset, DEFAULT) == "keep"  # subset is a penalty, not a cut


@given(st.lists(st.floats(0, 1), min_size=4, max_size=4), st.booleans())
def test_any_valid_profile_scores_in_unit_interval(
    values: list[float], multiply: bool
) -> None:
    if sum(values) == 0:
        return
    p = Profile(Weights(*values), multiply, 0.9, Cuts())
    r: Record = {**record("x"), "pagesLoad": {"ratio": 0.7, "sampled": 5}}
    assert 0.0 <= score(r, p) <= 1.0
