# Copyright (c) 2026 Krzysztof Rudnicki
"""``report --publish`` and ``candidates`` / ``probe`` as < 60 s batches."""

from __future__ import annotations

import json
lazy from pathlib import Path

from source_eval import report
from source_eval.app import MORE_WORK, App
from source_eval.candidates import catalog
from source_eval.state import Manifest
from tests.app_helpers import make_app
from tests.fakes import FakeClock, resp


def _published_run(tmp_path: Path) -> tuple[App, FakeClock, list[str]]:
    app, _, clock, lines = make_app(tmp_path)
    app.cmd_candidates()
    app.cmd_reference(None, 3)
    app.cmd_init_run("t", 2, Manifest([], 1, 1, 1))
    return app, clock, lines


def test_publish_resumes_where_the_budget_stopped(tmp_path: Path) -> None:
    app, clock, _ = _published_run(tmp_path)
    calls: list[str] = []

    class SlowWriter:
        def patch(self, path: str, data: dict[str, object]) -> None:
            calls.append(path)
            clock.advance(30.0)

    out = tmp_path / "r.json"
    assert app.cmd_report("t", out, SlowWriter(), budget=50.0) == MORE_WORK
    assert calls == [report.RTDB_PATH]
    assert out.exists()  # the report file is written every call
    assert app.cmd_report("t", out, SlowWriter(), budget=50.0) == 0
    assert calls == [report.RTDB_PATH, report.META_PATH]
    # Finished: the next publish starts over (a manual re-publish).
    assert app.cmd_report("t", out, SlowWriter(), budget=None) == 0
    assert calls[2:] == [report.RTDB_PATH, report.META_PATH]


def test_publish_with_no_time_left_does_nothing(tmp_path: Path) -> None:
    app, _, _ = _published_run(tmp_path)

    class Never:
        def patch(self, path: str, data: dict[str, object]) -> None:
            raise AssertionError(path)

    assert app.cmd_report("t", tmp_path / "r.json", Never(), budget=10.0) == MORE_WORK


def test_candidates_out_of_budget_asks_for_more(tmp_path: Path) -> None:
    app, transport, _, lines = make_app(tmp_path)
    transport.routes.insert(
        0, (catalog.MANGAYOMI_INDEX, [resp(429, "", {"retry-after": "20"})])
    )
    assert app.cmd_candidates(budget=10.0) == MORE_WORK
    assert not app.candidates_path.exists()
    assert any("budget" in line for line in lines)


def test_probe_skips_fresh_sources_and_stops_in_budget(tmp_path: Path) -> None:
    app, transport, clock, lines = make_app(tmp_path)
    app.cmd_candidates()
    cands = [c for c in catalog.load(app.candidates_path) if c.origin == "plugin"][:2]
    assert app.cmd_probe(cands, 2, budget=None, fresh=3600.0) == 0
    first = len(transport.sent)
    clock.advance(60.0)
    assert app.cmd_probe(cands, 2, budget=None, fresh=3600.0) == 0
    assert len(transport.sent) == first  # both probed within the hour
    assert any("fresh" in line for line in lines)
    clock.advance(7200.0)
    assert app.cmd_probe(cands, 2, budget=0.5, fresh=3600.0) == MORE_WORK
    assert len(transport.sent) == first


def test_report_progress_file_is_per_run(tmp_path: Path) -> None:
    app, clock, _ = _published_run(tmp_path)

    class Writer:
        def patch(self, path: str, data: dict[str, object]) -> None:
            clock.advance(40.0)

    app.cmd_report("t", tmp_path / "r.json", Writer(), budget=50.0)
    progress = app.s.state_dir / "runs" / "t" / "publish.json"
    assert json.loads(progress.read_text()) == {"records": True}
