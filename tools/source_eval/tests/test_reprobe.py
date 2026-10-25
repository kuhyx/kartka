# Copyright (c) 2026 Krzysztof Rudnicki
"""Re-probe of sources hard-cut last run (kuhy, 2026-10-25).

A source the previous published run hard-cut (``unreachable`` or
``blocking>=0.50``) gets one reachability request; only when it passes is it
measured against the full sample again. Its record says so.
"""

from __future__ import annotations

import json
from typing import cast
lazy from pathlib import Path

from source_eval.budget import Deadline
from source_eval.evaluate import Plan, evaluate
from source_eval.metrics import metrics
from source_eval.models import Candidate, Hit, SourceError
from source_eval.score import HARD_BLOCKING, UNREACHABLE, rank
from source_eval.state import Manifest, RunDir
from tests.app_helpers import make_app
from tests.fakes import FakeClock
from tests.test_evaluate import CAND, REFS, FakeBackend

REPROBE = Manifest(
    ["r1", "r2", "r3", "r4"], 3, 2, 2, reprobe=[CAND.id], reprobe_from="2026-W43"
)


class DownBackend(FakeBackend):
    """``popular`` (the reachability request) fails with ``down_kind``."""

    def __init__(self, down_kind: str | None) -> None:
        super().__init__()
        self.down_kind = down_kind

    def popular(self, cand: Candidate) -> list[Hit]:
        self.calls.append("popular")
        msg = "HTTP 521" if self.down_kind is None else "challenge"
        raise SourceError(msg, self.down_kind)


def _record(state: object, manifest: Manifest) -> dict[str, object]:
    rec = metrics(CAND, state, manifest, [], 1_800_000_000.0)  # type: ignore[arg-type]
    return rank([rec], {})[0]


def test_failed_reprobe_is_one_request_and_stays_hard_cut(tmp_path: Path) -> None:
    run = RunDir(tmp_path, "W44")
    state = run.source(CAND.id)
    backend = DownBackend(None)
    done = evaluate(
        CAND, backend, state, Plan(REFS, REPROBE), Deadline(FakeClock(), None)
    )
    assert done
    assert backend.calls == ["popular"]  # no search at all
    assert state.titles == {}
    again = run.source(CAND.id)  # persisted
    assert again.reprobe == {"passed": False, "kind": None, "previousRun": "2026-W43"}
    rec = _record(again, REPROBE)
    assert rec["reprobe"] == {"passed": False, "kind": None, "previousRun": "2026-W43"}
    assert "reprobe-only" in cast("list[str]", rec["flags"])
    assert UNREACHABLE in cast("list[str]", rec["cutReasons"])
    assert rec["unreachable"] is True
    assert rec["verdict"] == "cut"
    coverage = cast("dict[str, object]", rec["coverage"])
    assert coverage["ratio"] is None  # not measured, not "found nothing"


def test_challenged_reprobe_stays_blocking(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "W44").source(CAND.id)
    evaluate(
        CAND,
        DownBackend("cloudflare"),
        state,
        Plan(REFS, REPROBE),
        Deadline(FakeClock(), None),
    )
    rec = _record(state, REPROBE)
    reasons = cast("list[str]", rec["cutReasons"])
    assert HARD_BLOCKING in reasons
    assert UNREACHABLE not in reasons
    assert rec["verdict"] == "cut"


def test_passed_reprobe_measures_the_full_sample(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "W44").source(CAND.id)
    backend = FakeBackend()
    assert evaluate(
        CAND, backend, state, Plan(REFS, REPROBE), Deadline(FakeClock(), None)
    )
    assert set(state.titles) == {"r1", "r2", "r3", "r4"}
    rec = _record(state, REPROBE)
    assert rec["reprobe"] == {"passed": True, "kind": None, "previousRun": "2026-W43"}
    assert "reprobe-only" not in cast("list[str]", rec["flags"])


def test_webview_reprobe_counts_as_reachable(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "W44").source(CAND.id)
    evaluate(
        CAND,
        DownBackend("webview"),
        state,
        Plan(REFS, REPROBE),
        Deadline(FakeClock(), None),
    )
    assert state.reprobe is not None
    assert state.reprobe["passed"] is True
    assert state.titles  # measured as before: flagged, never cut


def test_not_listed_sources_get_no_reprobe_block(tmp_path: Path) -> None:
    plain = Manifest(["r1"], 3, 2, 2)
    state = RunDir(tmp_path, "W44").source(CAND.id)
    evaluate(CAND, FakeBackend(), state, Plan(REFS, plain), Deadline(FakeClock(), None))
    assert "reprobe" not in _record(state, plain)


def test_old_manifest_reads_without_reprobe(tmp_path: Path) -> None:
    path = tmp_path / "manifest.json"
    path.write_text(
        json.dumps({"sample": ["a"], "completeness": 1, "images": 1, "pages": 1})
    )
    loaded = Manifest.load(path)
    assert loaded is not None
    assert loaded.reprobe == []
    assert loaded.reprobe_from is None


def test_publish_records_hard_cuts_and_init_run_reprobes_them(tmp_path: Path) -> None:
    app, _, clock, _ = make_app(tmp_path)
    app.cmd_reference(None, 3)
    hard = json.dumps({"runId": "W43", "ids": ["suwayomi:7", "mangadex"]})
    (app.s.state_dir / "hard_cut.json").write_text(hard)
    assert app.cmd_init_run("W44", 2, Manifest([], 1, 1, 1), reprobe=True) == 0
    manifest = Manifest.load(RunDir(app.s.state_dir, "W44").manifest_path)
    assert manifest is not None
    assert manifest.reprobe == ["suwayomi:7", "mangadex"]
    assert manifest.reprobe_from == "W43"
    # The same run never re-probes its own hard cuts.
    (app.s.state_dir / "hard_cut.json").write_text(
        json.dumps({"runId": "W45", "ids": ["x"]})
    )
    app.cmd_init_run("W45", 2, Manifest([], 1, 1, 1), reprobe=True)
    same = Manifest.load(RunDir(app.s.state_dir, "W45").manifest_path)
    assert same is not None
    assert same.reprobe == []
    # Publishing writes the run's hard cuts for the next run.
    app.cmd_candidates()
    state = RunDir(app.s.state_dir, "W44").source("mangadex")
    state.aborted, state.done = "unreachable", True
    state.titles = {
        k: {"status": "error", "kind": None} for k in ("a", "b", "c", "d", "e")
    }
    state.save()
    clock.advance(1)

    class Writer:
        def patch(self, path: str, data: dict[str, object]) -> None:
            pass

    assert app.cmd_report("W44", tmp_path / "r.json", Writer()) == 0
    saved = json.loads((app.s.state_dir / "hard_cut.json").read_text())
    assert saved == {"runId": "W44", "ids": ["mangadex"]}


def test_report_without_publish_leaves_hard_cuts_alone(tmp_path: Path) -> None:
    app, _, _, _ = make_app(tmp_path)
    app.cmd_candidates()
    app.cmd_reference(None, 3)
    app.cmd_init_run("W44", 2, Manifest([], 1, 1, 1))
    assert app.cmd_report("W44", tmp_path / "r.json", None) == 0
    assert not (app.s.state_dir / "hard_cut.json").exists()
