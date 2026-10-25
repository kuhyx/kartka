# Copyright (c) 2026 Krzysztof Rudnicki
"""The weekly sample ramp (kuhy, 2026-10-25).

+50 titles a week while the previous run met the 2 h target, -50 when it
went over; never below 200 (the current sample) nor above 500.
"""

from __future__ import annotations

import json
lazy from pathlib import Path

from source_eval.ramp import CAP, FLOOR, STEP, TARGET_SECONDS, Ramp
from source_eval.state import Manifest, RunDir
from tests.app_helpers import make_app
from tests.fakes import FakeClock


def _week(ramp: Ramp, clock: FakeClock, run: str, seconds: float) -> int:
    sample = ramp.start(run)
    clock.advance(seconds)
    ramp.finish(run)
    return sample


def test_constants_match_the_decision() -> None:
    assert (FLOOR, CAP, STEP, TARGET_SECONDS) == (200, 500, 50, 7200.0)


def test_first_run_starts_at_the_floor(tmp_path: Path) -> None:
    assert Ramp(tmp_path / "ramp.json", FakeClock()).start("W1") == 200


def test_ramp_up_while_on_target_then_cap(tmp_path: Path) -> None:
    clock = FakeClock()
    ramp = Ramp(tmp_path / "ramp.json", clock)
    samples = [_week(ramp, clock, f"W{i}", 3600.0) for i in range(9)]
    assert samples == [200, 250, 300, 350, 400, 450, 500, 500, 500]


def test_ramp_down_when_over_then_floor(tmp_path: Path) -> None:
    clock = FakeClock()
    ramp = Ramp(tmp_path / "ramp.json", clock)
    assert _week(ramp, clock, "W1", 3600.0) == 200
    assert _week(ramp, clock, "W2", 3600.0) == 250
    assert _week(ramp, clock, "W3", 7201.0) == 300  # this one went over
    assert _week(ramp, clock, "W4", 7201.0) == 250
    assert _week(ramp, clock, "W5", 7201.0) == 200
    assert _week(ramp, clock, "W6", 7200.0) == 200  # floor; 7200 s is on target
    assert ramp.start("W7") == 250


def test_resumed_run_keeps_its_sample_and_start(tmp_path: Path) -> None:
    clock = FakeClock()
    path = tmp_path / "ramp.json"
    assert _week(Ramp(path, clock), clock, "W1", 100.0) == 200
    first = Ramp(path, clock).start("W2")
    clock.advance(5000.0)
    assert Ramp(path, clock).start("W2") == first == 250  # no re-ramp
    clock.advance(3000.0)
    assert Ramp(path, clock).finish("W2") == 8000.0  # since the first start
    state = json.loads(path.read_text())
    assert state["last"] == {"run": "W2", "sample": 250, "wallSeconds": 8000.0}
    assert state["current"] is None
    assert Ramp(path, clock).start("W3") == 200


def test_finish_of_an_unknown_run_changes_nothing(tmp_path: Path) -> None:
    clock = FakeClock()
    ramp = Ramp(tmp_path / "ramp.json", clock)
    ramp.start("W1")
    assert ramp.finish("other") is None
    assert ramp.current_sample("W1") == 200
    assert ramp.current_sample("other") is None


def test_override_is_used_and_recorded(tmp_path: Path) -> None:
    clock = FakeClock()
    ramp = Ramp(tmp_path / "ramp.json", clock)
    assert ramp.start("W1", sample=330) == 330
    clock.advance(10.0)
    ramp.finish("W1")
    assert ramp.start("W2") == 380


def test_commands_log_and_feed_init_run(tmp_path: Path) -> None:
    app, _, clock, lines = make_app(tmp_path)
    app.cmd_reference(None, 3)
    assert app.cmd_ramp_start("W1", None) == 0
    assert any(line.startswith("ramp: run W1 sample 200") for line in lines)
    assert app.cmd_init_run("W1", None, Manifest([], 1, 1, 1), ramp=True) == 0
    manifest = Manifest.load(RunDir(app.s.state_dir, "W1").manifest_path)
    assert manifest is not None
    assert len(manifest.sample) == 3  # 200 asked, only 3 reference titles
    clock.advance(42.0)
    assert app.cmd_ramp_finish("W1") == 0
    assert any("W1 took 42 s" in line for line in lines)
    assert (app.s.state_dir / "ramp.json").exists()


def test_init_run_with_ramp_needs_a_started_run(tmp_path: Path) -> None:
    app, _, _, lines = make_app(tmp_path)
    assert app.cmd_init_run("W9", None, Manifest([], 1, 1, 1), ramp=True) == 2
    assert any("ramp start" in line for line in lines)
