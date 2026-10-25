# Copyright (c) 2026 Krzysztof Rudnicki
"""pagesLoad factor, the KEEP_SCORE override and langScope."""

from __future__ import annotations

lazy from pathlib import Path

from source_eval.metrics import lang_scope, metrics, pages_load
from source_eval.models import Candidate
from source_eval.score import KEEP_SCORE, Record, rank, score
from source_eval.state import Manifest, RunDir
from tests.test_scoring import record


def perfect(
    rid: str,
    *,
    status: str = "final",
    challenge: float = 0.0,
    kinds: list[str] | None = None,
    p95: float = 0,
) -> Record:
    """Every metric at its best (score 1.0 before pagesLoad)."""
    return record(
        rid,
        coverage=1,
        complete=1,
        up=1,
        width=1400,
        p95=p95,
        status=status,
        challenge=challenge,
        kinds=kinds,
    )


def with_pages(rec: Record, ratio: float | None, sampled: int = 4) -> Record:
    rec["pagesLoad"] = {"ratio": ratio, "sampled": sampled}
    return rec


def test_keep_score_constant() -> None:
    assert KEEP_SCORE == 0.90


def test_pages_never_loading_scores_zero() -> None:
    best = with_pages(perfect("x"), 0.0)
    assert score(best) == 0.0
    assert score(with_pages(perfect("x"), 0.5)) == 0.5
    assert score(with_pages(perfect("x"), None, 0)) == 1.0
    assert score(perfect("x")) == 1.0  # no block at all


def test_zero_pages_falls_back_to_the_old_rules() -> None:
    ranked = rank([with_pages(perfect("x"), 0.0)], {})
    assert ranked[0]["score"] == 0.0
    assert ranked[0]["verdict"] == "keep"  # no cut reason, uptime final
    accruing = with_pages(perfect("y", status="accruing"), 0.0)
    assert rank([accruing], {})[0]["verdict"] == "pending"


def test_high_score_keeps_despite_cut_reasons() -> None:
    blocked = perfect("b", challenge=0.5, kinds=["cloudflare"])
    dup = perfect("d", challenge=0.5, kinds=["cloudflare"], p95=10)
    top = perfect("t")
    found = {"t": {"a", "b"}, "b": {"a", "b"}, "d": {"a", "b"}}
    ranked = {r["id"]: r for r in rank([dup, blocked, top], found)}
    assert ranked["d"]["verdict"] == "keep"
    assert ranked["d"]["cutReasons"] == ["blocking", "subset"]
    assert ranked["b"]["verdict"] == "keep"


def test_high_score_keeps_while_uptime_accrues() -> None:
    new = perfect("n", status="accruing")
    assert rank([new], {})[0]["verdict"] == "keep"
    unmeasured = record("u", coverage=None, complete=1, up=1, width=1400, p95=0)
    assert rank([unmeasured], {})[0]["verdict"] == "pending"  # scores 0.7


def test_just_below_keep_score_is_still_cut() -> None:
    rec = perfect("x", challenge=0.5, kinds=["403"])
    with_pages(rec, 0.89)
    out = rank([rec], {})[0]
    assert out["score"] == 0.89
    assert out["verdict"] == "cut"


def _state(tmp_path: Path, images: dict[str, dict[str, object]]) -> RunDir:
    run = RunDir(tmp_path, "r")
    state = run.source("suwayomi:1")
    state.images = images
    state.save()
    return run


def test_pages_load_from_stored_chapter_outcomes(tmp_path: Path) -> None:
    run = _state(
        tmp_path,
        {
            "a": {"pages": [{"width": 800}]},
            "b": {"pages": [{"width": 900}, {"width": 900}]},
            "c": {"error": "purchase this chapter", "kind": "webview", "pages": []},
            "d": {"pages": []},  # the source listed no pages
        },
    )
    assert pages_load(run.source("suwayomi:1")) == {"ratio": 0.5, "sampled": 4}
    assert pages_load(_state(tmp_path / "e", {}).source("suwayomi:1")) == {
        "ratio": None,
        "sampled": 0,
    }


def test_lang_scope() -> None:
    def cand(lang: str, origin: str = "suwayomi") -> Candidate:
        return Candidate("x", "X", lang, origin, "https://x.test")  # type: ignore[arg-type]

    assert lang_scope(cand("en")) == "en+ja"
    assert lang_scope(cand("ja")) == "en+ja"
    assert lang_scope(cand("en", "native")) == "en+ja"
    assert lang_scope(cand("all")) == "unrestricted"
    assert lang_scope(cand("all", "plugin")) == "unrestricted"


def test_metrics_carry_pages_load_and_lang_scope(tmp_path: Path) -> None:
    run = _state(tmp_path, {"a": {"pages": [{"width": 800}]}})
    cand = Candidate("suwayomi:1", "X", "all", "suwayomi", "https://x.test")
    m = metrics(cand, run.source(cand.id), Manifest(["k"], 1, 1, 1), [], 0.0)
    assert m["pagesLoad"] == {"ratio": 1.0, "sampled": 1}
    assert m["langScope"] == "unrestricted"
