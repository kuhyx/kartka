# Copyright (c) 2026 Krzysztof Rudnicki
"""The hosts-file lookup after a failed probe is bounded too.

``getaddrinfo`` for a dead domain stalled 40 s here (manhwaz.com,
2026-10-25); a probe that failed near the end of its budget must not wait
for it. A lookup that does not answer in time is "no answer" (``None``).
"""

from __future__ import annotations

from dataclasses import replace
import socket
import time
lazy from pathlib import Path

import pytest

from source_eval.app import MORE_WORK
from source_eval.budget import Deadline, RequestBudget
from source_eval.candidates import catalog
from source_eval.http import SystemClock
from source_eval.uptime import HOSTS_BLOCKED, RESOLVE_TIMEOUT, failed, lookup_window
from tests.app_helpers import make_app
from tests.fakes import FakeClock


def _stalled(host: str) -> list[str]:
    time.sleep(5.0)
    return ["0.0.0.0"]


def test_a_stalled_lookup_is_no_answer() -> None:
    start = time.monotonic()
    obs = failed(FakeClock(), "dead.test", _stalled, within=0.2)
    assert time.monotonic() - start < 1.0
    assert obs.kind is None
    assert failed(FakeClock(), "x", lambda h: ["0.0.0.0"], within=0.2).kind == (
        HOSTS_BLOCKED
    )


def test_no_time_left_skips_the_lookup() -> None:
    asked: list[str] = []

    def resolver(host: str) -> list[str]:
        asked.append(host)
        return []

    obs = failed(FakeClock(), "x", resolver, within=0.0)
    assert obs.kind is None
    assert asked == []


def test_lookup_window_follows_the_budget() -> None:
    clock = FakeClock()
    assert lookup_window(None) == RESOLVE_TIMEOUT
    assert lookup_window(RequestBudget(Deadline(clock, None))) == RESOLVE_TIMEOUT
    tight = RequestBudget(Deadline(clock, 2.5), min_start=1.0, grace=1.0)
    assert lookup_window(tight) == pytest.approx(1.5)
    clock.advance(9.0)
    assert lookup_window(tight) <= 0


def test_probe_with_a_stalled_resolver_ends_in_budget(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    app, transport, _, lines = make_app(tmp_path)
    app.cmd_candidates()
    plugins = [c for c in catalog.load(app.candidates_path) if c.origin == "plugin"]

    def stalled(*args: object, **kwargs: object) -> list[object]:
        time.sleep(10.0)
        raise socket.gaierror

    monkeypatch.setattr(socket, "getaddrinfo", stalled)
    app = type(app)(
        replace(app.s, interval=0.01, min_start=0.2, grace=0.5),
        SystemClock(),
        transport,  # no route for the plugin front pages: TransportError
        lines.append,
    )
    start = time.monotonic()
    assert app.cmd_probe(plugins, 8, budget=2.0, fresh=None) in {0, MORE_WORK}
    assert time.monotonic() - start < 2.0
