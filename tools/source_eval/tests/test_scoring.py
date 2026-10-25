# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import copy
from typing import Any

from hypothesis import given
from hypothesis import strategies as st

from source_eval.score import Record, cut_reasons, rank, score


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
    # DOCS-contracts §5 example values; the formula, not the printed 0.81, wins.
    example = record("x", coverage=0.788, complete=0.97, up=0.964, width=1100, p95=1300)
    assert score(example) == 0.852


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


def test_rank_verdicts_and_subset() -> None:
    # The score alone decides the verdict; cutReasons only explain it.
    def strong(rid: str, **kw: Any) -> Record:  # noqa: ANN401
        return record(rid, complete=1, p95=0, **kw)

    records = [
        strong("big", coverage=0.9),
        strong("dup", coverage=0.85),
        strong("narrow", coverage=0.85, width=2000),
        strong("new", coverage=0.7, status="accruing"),
        strong("plugin", coverage=None, origin="plugin"),
        record("blocked", coverage=0.95, challenge=0.5, complete=0.5, p95=0),
    ]
    found = {
        "big": {"a", "b", "c", "d"},
        "dup": {"a", "b", "c"},
        "narrow": {"a", "b", "c"},
        "new": {"z"},
        "blocked": {"a", "b", "c", "d", "e"},
    }
    ranked = {r["id"]: r for r in rank(copy.deepcopy(records), found)}
    assert [ranked[k]["rank"] for k in ("narrow", "big", "dup")] == [1, 2, 3]
    assert ranked["big"]["verdict"] == "keep"
    assert ranked["blocked"]["verdict"] == "cut"
    assert ranked["blocked"]["cutReasons"] == ["blocking"]
    # "narrow" outranks "big" (wider images) and is the best superset of "dup".
    assert ranked["dup"]["subsetOf"] == {"sourceId": "narrow", "overlap": 1.0}
    assert ranked["dup"]["cutReasons"] == ["subset"]
    assert ranked["dup"]["verdict"] == "keep"  # explanatory only: score 0.934
    assert ranked["narrow"]["subsetOf"] is None  # outranks "big"
    assert ranked["big"]["subsetOf"] is None  # "narrow" lacks "d"
    assert ranked["new"]["verdict"] == "cut"  # measured, score 0.889, uptime accruing
    assert ranked["new"]["cutReasons"] == []
    assert ranked["plugin"]["verdict"] == "pending"  # nothing measured


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
