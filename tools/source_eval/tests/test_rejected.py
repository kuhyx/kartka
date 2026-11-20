# Copyright (c) 2026 Krzysztof Rudnicki
"""Permanent reject at <= 0.65 (kuhy, 2026-11-20): removed, never re-judged."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, cast
lazy from pathlib import Path

from source_eval import publishing, rejected, report
from source_eval.candidates import catalog
from source_eval.fsio import write_json_atomic
from source_eval.models import Candidate, RefTitle
from source_eval.state import Manifest, RunDir, sha1
from tests.app_helpers import make_app

if TYPE_CHECKING:
    from source_eval.app import App
    from source_eval.score import Record

BAD = Candidate("suwayomi:1", "Bad", "en", "suwayomi", "https://bad.test", "eu.b")
STUB = Candidate("plugin:legacy-x", "X", "en", "plugin", "https://x.test")
OLD = {"score": 0.1, "runId": "2026-W40", "rejectedAt": "2026-10-04T12:00:00Z"}


def rec(rid: str, score: float, verdict: str = "cut", **extra: object) -> Record:
    return {
        "id": rid,
        "score": score,
        "verdict": verdict,
        "coverage": {"ratio": 0.1},
        "flags": [],
        **extra,
    }


def test_only_a_measured_cut_at_or_below_the_bar_is_rejected() -> None:
    assert rejected.REJECT_SCORE == 0.65
    assert rejected.eligible(rec("a", 0.65))
    assert rejected.eligible(rec("a", 0.0, cutReasons=["unreachable"]))
    assert not rejected.eligible(rec("a", 0.651))
    assert not rejected.eligible(rec("a", 0.2, "pending"))
    assert not rejected.eligible(rec("a", 0.2, "keep"))  # a low custom keep bar
    assert not rejected.eligible(rec("a", 0.2, coverage={"ratio": None}))
    assert not rejected.eligible(rec("a", 0.2, flags=["reprobe-only"]))


def test_apply_drops_rejected_records_renumbers_and_counts() -> None:
    sources = [rec("keep", 0.9, "keep"), rec("low", 0.3), rec("old", 0.8)]
    sources.append(rec("mid", 0.7))
    for rank, r in enumerate(sources, start=1):
        r["rank"] = rank
    meta: dict[str, object] = {"tested": 4, "verdicts": {}}
    out: dict[str, object] = {"sources": sources, "meta": meta}
    merged = rejected.apply(out, {"old": OLD}, "2026-W44", 1_800_000_000.0)
    assert merged == {
        "old": OLD,  # never re-judged, even at a better score
        "low": {
            "score": 0.3,
            "runId": "2026-W44",
            "rejectedAt": "2027-01-15T08:00:00Z",
        },
    }
    kept = cast("list[Record]", out["sources"])
    assert [(r["id"], r["rank"]) for r in kept] == [("keep", 1), ("mid", 2)]
    assert out["rejected"] == merged
    assert meta == {
        "tested": 2,
        "verdicts": {"keep": 1, "cut": 1, "pending": 0},
        "rejected": 2,
    }


def test_load_without_or_with_a_file(tmp_path: Path) -> None:
    assert rejected.load(tmp_path) == {}
    write_json_atomic(tmp_path / rejected.REJECTED_FILE, {"old": OLD})
    assert rejected.load(tmp_path) == {"old": OLD}
    cands = [BAD, Candidate("old", "Old", "en", "suwayomi", "https://o.test")]
    assert rejected.without(cands, tmp_path) == [BAD]


def _run(tmp_path: Path) -> App:
    app, _, _, _ = make_app(tmp_path)
    catalog.save(app.candidates_path, [BAD, STUB])
    ref = app.reference()
    ref.titles = [RefTitle(k, (k,), country="JP") for k in ("a", "b")]
    ref.save()
    run = RunDir(app.s.state_dir, "W44")
    Manifest(["a", "b"], 1, 1, 1, all_chapters=True).save(run.manifest_path)
    for cand in (BAD, STUB):
        state = run.source(cand.id)
        state.titles = {"a": {"status": "missing"}, "b": {"status": "missing"}}
        state.done = True
        state.save()
    write_json_atomic(app.s.state_dir / rejected.REJECTED_FILE, {"old": OLD})
    return app


def test_a_dry_run_report_changes_no_state(tmp_path: Path) -> None:
    app = _run(tmp_path)
    lines: list[str] = []
    app.out = lines.append
    out = tmp_path / "r.json"
    assert app.cmd_report("W44", out, None) == 0
    data = json.loads(out.read_text())
    assert [r["id"] for r in data["sources"]] == [STUB.id]  # pending stays
    assert sorted(data["rejected"]) == ["old", BAD.id]
    assert data["meta"]["rejected"] == 2
    assert "rejected: 2 (1 new); dry run, not saved" in lines
    assert rejected.load(app.s.state_dir) == {"old": OLD}


def test_publish_deletes_rejected_records_then_saves_them(tmp_path: Path) -> None:
    app = _run(tmp_path)
    calls: list[tuple[str, dict[str, object]]] = []

    class Writer:
        def patch(self, path: str, data: dict[str, object]) -> None:
            calls.append((path, data))

    assert app.cmd_report("W44", tmp_path / "r.json", Writer()) == 0
    assert [path for path, _ in calls] == [
        report.RTDB_PATH,
        report.RTDB_PATH,
        report.META_PATH,
    ]
    assert list(calls[0][1]) == [sha1(STUB.id)]
    assert calls[1][1] == {sha1(BAD.id): None, sha1("old"): None}
    assert calls[2][1]["rejected"] == 2
    saved = rejected.load(app.s.state_dir)
    assert saved["old"] == OLD
    assert saved[BAD.id]["runId"] == "W44"
    # Never re-judged: no later run or probe selects it, nor re-probes it.
    assert [c.id for c in app.select([], installed=False)] == [STUB.id]
    assert app.select([BAD.id], installed=False) == []
    write_json_atomic(
        app.s.state_dir / publishing.HARD_CUT_FILE,
        {"runId": "W44", "ids": [BAD.id, "x"]},
    )
    assert publishing.previous_hard_cuts(app.s.state_dir, "W45") == (["x"], "W44")
