# Copyright (c) 2026 Krzysztof Rudnicki
"""``systemd/weekly.sh`` and ``probe.sh``: loops of < 60 s batches.

Driven with a stub ``uv`` on PATH that logs each call and exits with the
next code scripted for its subcommand (10 = MORE_WORK, call again).
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest

SYSTEMD = Path(__file__).resolve().parents[1] / "systemd"
STUB = """#!/bin/bash
# Stub uv: log the source-eval arguments, exit with the next scripted code.
set -euo pipefail
shift 4  # run --frozen --project <dir>
[[ $1 == source-eval ]] || exit 99
shift
echo "$*" >>"${STUB_LOG}"
plan="${STUB_PLAN}/$1"
[[ -s ${plan} ]] || exit 0
code="$(head -n 1 "${plan}")"
tail -n +2 "${plan}" >"${plan}.rest"
mv "${plan}.rest" "${plan}"
exit "${code}"
"""


def _run(
    tmp_path: Path, script: str, plan: dict[str, list[int]], **env: str
) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    bin_dir, plan_dir = tmp_path / "bin", tmp_path / "plan"
    bin_dir.mkdir(exist_ok=True)
    plan_dir.mkdir(exist_ok=True)
    stub = bin_dir / "uv"
    stub.write_text(STUB)
    stub.chmod(0o755)
    for cmd, codes in plan.items():
        (plan_dir / cmd).write_text("".join(f"{c}\n" for c in codes))
    log = tmp_path / "calls.log"
    full_env = {
        **os.environ,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "STUB_LOG": str(log),
        "STUB_PLAN": str(plan_dir),
        "KARTKA_EVAL_RUN": "2026-W44",
        **env,
    }
    full_env.pop("KARTKA_EVAL_SAMPLE", None)
    done = subprocess.run(
        [str(SYSTEMD / script)],
        env={**full_env, **env},
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    calls = log.read_text().splitlines() if log.exists() else []
    return done, calls


def test_weekly_loops_each_step_until_it_is_done(tmp_path: Path) -> None:
    done, calls = _run(tmp_path, "weekly.sh", {"run": [10, 10, 0], "enrich": [10, 0]})
    assert done.returncode == 0, done.stderr
    assert calls == [
        "ramp start --run 2026-W44",
        "candidates --budget 50",
        "reference --budget 50",
        "init-run --run 2026-W44 --ramp --reprobe",
        "enrich --run 2026-W44 --budget 50",
        "enrich --run 2026-W44 --budget 50",
        *["run --run 2026-W44 --workers 128 --inflight 32 --budget 50"] * 3,
        "report --run 2026-W44 --publish --budget 50",
        "ramp finish --run 2026-W44",
    ]


def test_weekly_passes_a_sample_override(tmp_path: Path) -> None:
    done, calls = _run(tmp_path, "weekly.sh", {}, KARTKA_EVAL_SAMPLE="300")
    assert done.returncode == 0, done.stderr
    assert calls[0] == "ramp start --run 2026-W44 --sample 300"


def test_weekly_stops_on_a_real_failure(tmp_path: Path) -> None:
    done, calls = _run(tmp_path, "weekly.sh", {"run": [10, 3]})
    assert done.returncode == 3
    assert not any(c.startswith(("report", "ramp finish")) for c in calls)


def test_weekly_gives_up_after_too_many_batches(tmp_path: Path) -> None:
    done, calls = _run(
        tmp_path, "weekly.sh", {"run": [10] * 9}, KARTKA_EVAL_MAX_BATCHES="3"
    )
    assert done.returncode != 0
    assert sum(c.startswith("run ") for c in calls) == 3
    assert "3 batches" in done.stderr


def test_weekly_survives_a_hard_stop_with_a_warning(tmp_path: Path) -> None:
    done, calls = _run(tmp_path, "weekly.sh", {"run": [124, 0]})
    assert done.returncode == 0, done.stderr
    assert sum(c.startswith("run ") for c in calls) == 2
    assert "hard stop" in done.stderr


@pytest.mark.parametrize("budget", ["50", "40"])
def test_budget_is_configurable(tmp_path: Path, budget: str) -> None:
    done, calls = _run(tmp_path, "weekly.sh", {}, KARTKA_EVAL_BUDGET=budget)
    assert done.returncode == 0, done.stderr
    assert f"candidates --budget {budget}" in calls


def test_probe_loops_until_every_source_is_probed(tmp_path: Path) -> None:
    done, calls = _run(tmp_path, "probe.sh", {"probe": [10, 0]})
    assert done.returncode == 0, done.stderr
    assert calls == ["probe --workers 64 --fresh 10800 --budget 50"] * 2
