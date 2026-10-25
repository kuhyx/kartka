# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import copy
from typing import Any

from hypothesis import given
from hypothesis import strategies as st

from source_eval.score import Record, cut_reasons, rank, round3, score


def record(  # noqa: PLR0913
    rid: str,
    *,
    coverage: float | None = 0.8,
    complete: float | None = 0.9,
    up: float | None = 1.0,
    status: str = "final",
    width: float | None = 1200,
    p95: float | None = 1000,
    challenge: float = 0.0,
    kinds: list[str] | None = None,
    origin: str = "suwayomi",
) -> Record:
    return {
        "id": rid,
        "origin": origin,
        "coverage": {"ratio": coverage},
        "chapterCompleteness": {"medianRatio": complete},
        "uptime": {"ratio": up, "status": status},
        "imageQuality": {"medianWidthPx": width},
        "latencyMs": {"p95": p95},
        "blocking": {
            "challengeRate": challenge,
            **({} if kinds is None else {"kinds": kinds}),
        },
    }


def test_score_matches_contract_formula_example() -> None:
    # DOCS-contracts §5 example values, scored as a run without the merged
    # coverage (legacy split): 0.5 * (0.6 * .788 + 0.4 * .97) + 0.2 * .964
    # + 0.15 * 1 (1100 px >= 1067) + 0.15 * (1 - 1300 / 5000).
    example = record("x", coverage=0.788, complete=0.97, up=0.964, width=1100, p95=1300)
    assert score(example) == 0.884
    merged: Record = {**example, "coverage": {"ratio": 0.788, "completeRatio": 0.7}}
    assert score(merged) == round3(0.5 * 0.7 + 0.2 * 0.964 + 0.15 + 0.111)


def test_image_quality_is_full_from_1067_px() -> None:
    def quality(width: float) -> float:
        perfect = record("x", coverage=1, complete=1, up=1, width=width, p95=0)
        return score(perfect)

    assert quality(1067) == quality(4000) == 1.0
    assert quality(1067 / 2) == round3(0.85 + 0.15 * 0.5)


def test_round3_rounds_the_exact_value_half_up() -> None:
    assert round3(0.0625) == 0.063  # an exact binary tie: round() gives 0.062
    assert round3(1.0005) == 1.0  # 1.0005 is stored just below the tie
    assert round3(1.0) == 1.0


def test_score_caps_and_missing_metrics() -> None:
    assert score(record("x", coverage=1, complete=1, up=1, width=5000, p95=0)) == 1.0
    assert (
        score(record("x", coverage=None, complete=None, up=None, width=None, p95=None))
        == 0.0
    )
    assert score(record("x", coverage=0, complete=0, up=0, width=0, p95=99999)) == 0.0


@given(
    st.floats(0, 1),
    st.floats(0, 1),
    st.floats(0, 1),
    st.floats(0, 10000),
    st.floats(0, 100000),
)
def test_score_in_unit_interval(
    cov: float, comp: float, up: float, width: float, p95: float
) -> None:
    assert (
        0.0
        <= score(record("x", coverage=cov, complete=comp, up=up, width=width, p95=p95))
        <= 1.0
    )


def test_cut_reasons() -> None:
    assert cut_reasons(record("x")) == []
    assert cut_reasons(record("x", up=0.9)) == ["uptime<0.95"]
    assert cut_reasons(record("x", up=0.9, status="accruing")) == []
    assert cut_reasons(record("x", challenge=0.01)) == ["blocking"]
    assert cut_reasons(record("x", challenge=0.06, kinds=["cloudflare"])) == [
        "blocking"
    ]
    assert cut_reasons(record("x", coverage=0.5)) == ["coverage<0.60"]
    assert cut_reasons(record("x", coverage=None)) == []


def strong(rid: str, **kw: Any) -> Record:  # noqa: ANN401
    """Full uptime, completeness, width and speed; coverage as given."""
    return record(rid, complete=1, p95=0, **kw)


def test_rank_verdicts_and_the_graded_subset_penalty() -> None:
    records = [
        strong("big", coverage=0.9),  # 0.97
        strong("dup", coverage=0.85),  # 0.955 base, all of it on big
        strong("half", coverage=0.85),  # half of it on big
        strong("low", coverage=0.85),  # a quarter on big: no penalty
        strong("wide", coverage=0.85, width=1300),  # big is narrower
        {**strong("hard", coverage=0.9), "blocking": {"hardRate": 0.6}},
        strong("onhard", coverage=0.85),  # only on the hard-cut source
        strong("plugin", coverage=None, origin="plugin"),
        record("blocked", coverage=0.95, challenge=0.5, complete=0.5, p95=0),
    ]
    found = {
        "big": {"a", "b", "c", "d"},
        "dup": {"a", "b", "c"},
        "half": {"a", "b", "x", "y"},
        "low": {"a", "s", "t", "u"},
        "wide": {"a", "b", "c"},
        "hard": {"a", "p", "q", "r"},
        "onhard": {"p", "q"},
        "blocked": {"m"},
    }
    ranked = {r["id"]: r for r in rank(copy.deepcopy(records), found)}
    assert ranked["big"]["rank"] == 1  # "hard" ties on score, "big" < "hard"
    assert (ranked["big"]["verdict"], ranked["hard"]["verdict"]) == ("keep", "cut")
    assert ranked["hard"]["cutReasons"] == ["blocking>=0.50"]
    assert ranked["dup"]["subsetOf"] == {"sourceId": "big", "overlap": 1.0}
    assert ranked["dup"]["cutReasons"] == ["subset"]
    assert ranked["dup"]["score"] == 0.478  # the unrounded 0.955 x 0.5
    assert ranked["dup"]["defaultScore"] == ranked["dup"]["score"]
    assert ranked["dup"]["verdict"] == "cut"
    assert ranked["half"]["subsetOf"] == {"sourceId": "big", "overlap": 0.5}
    assert ranked["half"]["score"] == 0.716
    for free in ("low", "wide", "onhard"):
        assert ranked[free]["subsetOf"] is None, free
        assert (ranked[free]["score"], ranked[free]["verdict"]) == (0.955, "keep")
    assert ranked["blocked"]["cutReasons"] == ["blocking"]
    assert ranked["blocked"]["verdict"] == "cut"  # by score: 0.885
    assert ranked["plugin"]["verdict"] == "pending"  # nothing measured
    # The penalty re-ranks: "dup" (0.478) falls below "plugin" (0.5).
    assert [r["id"] for r in rank(copy.deepcopy(records), found)][-3:] == [
        "half",
        "plugin",
        "dup",
    ]


def test_subset_eligibility_is_the_base_ranking_without_feedback() -> None:
    """ "x" is itself penalised (half of it on "z") and ends up cut, yet it
    still covers "y": who covers whom is decided once, before any penalty."""
    z, x, y = (
        strong("z", coverage=0.9),
        strong("x", coverage=0.88),
        strong("y", coverage=0.85),
    )
    found = {"z": {"m", "o"}, "x": {"m", "n"}, "y": {"n"}}
    ranked = {r["id"]: r for r in rank([z, x, y], found)}
    assert ranked["x"]["subsetOf"] == {"sourceId": "z", "overlap": 0.5}
    assert ranked["x"]["verdict"] == "cut"
    assert ranked["y"]["subsetOf"] == {"sourceId": "x", "overlap": 1.0}
    assert ranked["y"]["score"] == 0.478


def test_subset_needs_comparable_images() -> None:
    # Only "b" scores >= KEEP_SCORE; a cut source is never a covering one.
    no_width = record("a", coverage=0.9, width=None, complete=1, p95=0)
    measured = record("b", coverage=0.8, complete=1, p95=0)
    unknown_b = record("c", coverage=0.7, width=None, complete=1, p95=0)
    wide = record("d", coverage=0.3, width=1400, complete=1, p95=0)
    found = {"a": {"x"}, "b": {"x"}, "c": {"x"}, "d": {"x"}}
    ranked = {r["id"]: r for r in rank([no_width, measured, unknown_b, wide], found)}
    assert ranked["b"]["rank"] == 1  # "a" scores low for its unknown width
    assert ranked["a"]["verdict"] == "cut"
    assert ranked["a"]["subsetOf"] == {"sourceId": "b", "overlap": 1.0}
    assert ranked["d"]["subsetOf"] is None  # nobody above is known to be as wide
    assert ranked["c"]["subsetOf"] == {"sourceId": "b", "overlap": 1.0}


def test_rank_tie_break_prefers_native() -> None:
    a = record("zz", origin="native")
    b = record("aa", origin="suwayomi")
    ordered = rank([b, a], {})
    assert [r["id"] for r in ordered] == ["zz", "aa"]


def test_webview_only_challenges_are_not_a_cut_reason() -> None:
    allmanga = record("a", challenge=0.06, kinds=["webview"], complete=1, p95=0)
    assert cut_reasons(allmanga) == []
    assert rank([allmanga], {})[0]["verdict"] == "keep"
    weak = record("w", challenge=0.06, kinds=["webview"])  # score 0.869
    out = rank([weak], {})[0]
    assert out["cutReasons"] == []
    assert out["verdict"] == "cut"  # no reason listed, yet the score is too low


def test_webview_mixed_with_a_real_challenge_still_cuts() -> None:
    mixed = record("m", challenge=0.1, kinds=["captcha", "webview"])
    assert cut_reasons(mixed) == ["blocking"]
