# Copyright (c) 2026 Krzysztof Rudnicki
"""The weekly sample ramp (kuhy, 2026-10-25).

Each weekly run measures ``FLOOR`` titles or more: ``STEP`` more than the
previous run when that run finished within ``TARGET_SECONDS``, ``STEP``
fewer when it went over, clamped to ``[FLOOR, CAP]``. A run's wall time is
from its first ``ramp start`` to ``ramp finish`` (after the publish), so a
run resumed after a crash or a reboot counts the whole span.

State, in the weekly state dir (``ramp.json``)::

    {"current": {"run", "sample", "startedAt"} | null,
     "last": {"run", "sample", "wallSeconds"} | null,
     "history": [last, ...]}   # newest last, capped
"""

from __future__ import annotations

from typing import TYPE_CHECKING, cast

from source_eval.fsio import read_json, write_json_atomic

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from source_eval.http import Clock

FLOOR, CAP, STEP = 200, 500, 50
TARGET_SECONDS = 2 * 3600.0
_HISTORY = 52


class Ramp:
    """``ramp.json``: the sample of the current run and how the last one went."""

    def __init__(self, path: Path, clock: Clock) -> None:
        """Load ``path`` (or start with no history)."""
        self.path = path
        self._clock = clock
        data = cast("dict[str, object]", read_json(path, {}))
        self.current = cast("dict[str, object] | None", data.get("current"))
        self.last = cast("dict[str, object] | None", data.get("last"))
        self.history = cast("list[dict[str, object]]", data.get("history", []))

    def _save(self) -> None:
        write_json_atomic(
            self.path,
            {"current": self.current, "last": self.last, "history": self.history},
        )

    def next_sample(self) -> int:
        """The rule applied to the last finished run (``FLOOR`` with none)."""
        if self.last is None:
            return FLOOR
        sample = int(cast("int", self.last["sample"]))
        wall = float(cast("float", self.last["wallSeconds"]))
        step = STEP if wall <= TARGET_SECONDS else -STEP
        return max(FLOOR, min(CAP, sample + step))

    def current_sample(self, run_id: str) -> int | None:
        """The sample ``run_id`` started with, if it is the current run."""
        if self.current is None or self.current["run"] != run_id:
            return None
        return int(cast("int", self.current["sample"]))

    def start(self, run_id: str, sample: int | None = None) -> int:
        """Start (or resume) ``run_id``; returns its sample.

        Idempotent per run: a resumed run keeps its sample and start time.
        ``sample`` overrides the rule (``KARTKA_EVAL_SAMPLE``) and is recorded
        like any other, so the next run ramps from it.
        """
        have = self.current_sample(run_id)
        if have is not None:
            return have
        chosen = self.next_sample() if sample is None else sample
        self.current = {"run": run_id, "sample": chosen, "startedAt": self._clock.now()}
        self._save()
        return chosen

    def finish(self, run_id: str) -> float | None:
        """Close ``run_id``: its wall seconds (``None`` if it is not current)."""
        if self.current is None or self.current["run"] != run_id:
            return None
        wall = self._clock.now() - float(cast("float", self.current["startedAt"]))
        self.last = {
            "run": run_id,
            "sample": self.current["sample"],
            "wallSeconds": round(wall, 1),
        }
        self.history = [*self.history, self.last][-_HISTORY:]
        self.current = None
        self._save()
        return round(wall, 1)

    def describe(self, run_id: str) -> str:
        """One log line: this run's sample and why."""
        last = self.last
        why = (
            "no previous run"
            if last is None
            else f"previous {last['run']}: {last['sample']} titles in"
            f" {float(cast('float', last['wallSeconds'])):.0f} s"
        )
        return (
            f"ramp: run {run_id} sample {self.current_sample(run_id)}"
            f" ({why}; target {TARGET_SECONDS:.0f} s, step {STEP},"
            f" floor {FLOOR}, cap {CAP})"
        )


def ramp_start(
    ramp: Ramp, run_id: str, sample: int | None, out: Callable[[str], None]
) -> int:
    """``ramp start``: start (or resume) ``run_id`` and log its sample."""
    ramp.start(run_id, sample)
    out(ramp.describe(run_id))
    return 0


def ramp_finish(ramp: Ramp, run_id: str, out: Callable[[str], None]) -> int:
    """``ramp finish``: record ``run_id``'s wall time for the next run."""
    wall = ramp.finish(run_id)
    if wall is None:
        out(f"ramp: {run_id} is not the current run; nothing recorded")
    else:
        out(f"ramp: {run_id} took {wall:.0f} s; next sample {ramp.next_sample()}")
    return 0
