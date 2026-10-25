# Copyright (c) 2026 Krzysztof Rudnicki
"""The hard per-invocation deadline and per-host start spacing (2026-10-25).

Every invocation must end within its ``--budget`` including any in-flight
request, and request starts to one host stay >= the gate interval apart
however many lanes run at once.
"""

from __future__ import annotations

from dataclasses import replace
import itertools
import json
import threading
import time
lazy from pathlib import Path

import pytest

from source_eval.app import MORE_WORK
from source_eval.budget import BudgetExhausted, Deadline, RequestBudget
from source_eval.gate import HostGate
from source_eval.http import (
    BoundedTransport,
    Request,
    Response,
    SystemClock,
    TransportTimeoutError,
)
from source_eval.models import Candidate
from source_eval.polite import Observation, PoliteClient
from source_eval.state import Manifest, RunDir
from tests.app_helpers import SUWA, make_app
from tests.fakes import FakeClock, FakeTransport, resp


class SlowTransport:
    """Answers after ``delay`` real seconds; records every start time."""

    def __init__(self, delay: float) -> None:
        self.delay = delay
        self.starts: list[tuple[str, float]] = []
        self._lock = threading.Lock()

    def send(self, request: Request) -> Response:
        with self._lock:
            self.starts.append((request.url, time.time()))
        time.sleep(self.delay)
        return resp(200, {"data": {"source": {"id": "1"}}})


def test_deadline_counts_from_the_given_start() -> None:
    clock = FakeClock()
    d = Deadline(clock, 10.0, start=clock.now() - 4.0)
    assert d.remaining() == pytest.approx(6.0)
    assert not d.expired()
    assert Deadline(clock, None).remaining() == float("inf")
    assert Deadline(clock, None).until is None


def test_request_budget_clips_or_refuses() -> None:
    clock = FakeClock()
    rb = RequestBudget(Deadline(clock, 30.0), min_start=5.0, grace=1.0)
    assert rb.timeout(20.0) == 20.0
    clock.advance(15.0)  # 15 s left, 14 after grace
    assert rb.timeout(20.0) == pytest.approx(14.0)
    assert rb.latest_start() == pytest.approx(clock.now() + 9.0)
    clock.advance(10.0)  # 4 s after grace: below min_start
    with pytest.raises(BudgetExhausted):
        rb.timeout(20.0)
    assert rb.timeout(3.0) == 3.0  # a short request still fits
    assert RequestBudget(None).timeout(20.0) == 20.0
    assert RequestBudget(None).latest_start() is None


def test_bounded_transport_caps_wall_time() -> None:
    bounded = BoundedTransport(SlowTransport(3.0))
    start = time.monotonic()
    with pytest.raises(TransportTimeoutError):
        bounded.send(Request("GET", "https://slow.test/", timeout=0.2))
    assert time.monotonic() - start < 0.6
    fast = BoundedTransport(SlowTransport(0.0))
    assert fast.send(Request("GET", "https://fast.test/", timeout=1.0)).status == 200


def test_bounded_transport_reraises_inner_errors() -> None:
    t = FakeTransport()
    t.add("https://a.test/", TransportTimeoutError("read timed out"))
    with pytest.raises(TransportTimeoutError, match="read timed out"):
        BoundedTransport(t).send(Request("GET", "https://a.test/"))


def _client(
    tmp_path: Path, transport: object, clock: object, budget: RequestBudget
) -> tuple[PoliteClient, list[Observation]]:
    seen: list[Observation] = []
    gate = HostGate(tmp_path / "hosts.json", 2.0, clock)  # type: ignore[arg-type]
    client = PoliteClient(
        transport,  # type: ignore[arg-type]
        gate,
        clock,  # type: ignore[arg-type]
        None,
        "ua",
        observe=seen.append,
        budget=budget,
    )
    return client, seen


def test_clipped_timeout_is_the_budget_not_a_failure(tmp_path: Path) -> None:
    clock = SystemClock()
    budget = RequestBudget(Deadline(clock, 0.5), min_start=0.1, grace=0.1)
    client, seen = _client(
        tmp_path, BoundedTransport(SlowTransport(5.0)), clock, budget
    )
    start = time.monotonic()
    with pytest.raises(BudgetExhausted):
        client.fetch(Request("GET", "https://slow.test/", timeout=20.0))
    assert time.monotonic() - start < 0.5
    assert seen == []  # nothing about the source was learned


def test_full_timeout_is_recorded_as_a_failure(tmp_path: Path) -> None:
    clock = SystemClock()
    budget = RequestBudget(Deadline(clock, 30.0), min_start=0.1, grace=0.1)
    client, seen = _client(
        tmp_path, BoundedTransport(SlowTransport(5.0)), clock, budget
    )
    with pytest.raises(TransportTimeoutError):
        client.fetch(Request("GET", "https://slow.test/", timeout=0.2))
    assert [o.ok for o in seen] == [False]


def test_gate_refuses_a_slot_past_the_latest_start(tmp_path: Path) -> None:
    clock = FakeClock()
    gate = HostGate(tmp_path / "hosts.json", 2.0, clock)
    gate.wait("a.test")
    with pytest.raises(BudgetExhausted):
        gate.wait("a.test", latest=clock.now() + 1.0)
    assert clock.slept == []  # never slept just to refuse
    gate.wait("a.test", latest=clock.now() + 2.0)
    assert clock.slept == [2.0]


def test_backoff_past_the_deadline_stops(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(429, "", {"retry-after": "20"}))
    budget = RequestBudget(Deadline(clock, 15.0), min_start=1.0, grace=1.0)
    client, seen = _client(tmp_path, t, clock, budget)
    with pytest.raises(BudgetExhausted):
        client.fetch(Request("GET", "https://a.test/x"))
    assert [o.status for o in seen] == [429]
    assert clock.slept == []


def test_starts_per_host_stay_spaced_under_concurrency(tmp_path: Path) -> None:
    interval, clock = 0.05, SystemClock()
    slow = SlowTransport(0.08)  # longer than the interval: requests overlap
    gate = HostGate(tmp_path / "hosts.json", interval, clock)
    # Two in-flight slots for eight lanes: a lane often waits for a slot
    # after its host slot came up; the claim must still be the real start.
    slots = threading.Semaphore(2)
    client = PoliteClient(slow, gate, clock, None, "ua", inflight=slots)

    def lane(host: str) -> None:
        for i in range(4):
            client.fetch(Request("GET", f"https://{host}/{i}"))

    hosts = ["a.test", "b.test"] * 4
    threads = [threading.Thread(target=lane, args=(h,)) for h in hosts]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    for host in ("a.test", "b.test"):
        starts = sorted(t for url, t in slow.starts if host in url)
        assert len(starts) == 16
        gaps = [b - a for a, b in itertools.pairwise(starts)]
        assert min(gaps) >= interval * 0.95


def test_gate_flushes_last_times_when_asked(tmp_path: Path) -> None:
    clock = FakeClock()
    gate = HostGate(tmp_path / "hosts.json", 2.0, clock, flush_every=60.0)
    gate.wait("a.test")
    gate.wait("b.test")
    gate.flush()
    saved = json.loads((tmp_path / "hosts.json").read_text())
    assert set(saved) == {"a.test", "b.test"}


def test_run_never_outlives_its_budget(tmp_path: Path) -> None:
    """A source whose every request hangs: the batch still ends in budget."""
    app, _, _, lines = make_app(tmp_path)
    app = type(app)(
        replace(app.s, interval=0.01, min_start=0.2, grace=0.1),
        SystemClock(),
        BoundedTransport(SlowTransport(30.0)),
        lines.append,
    )
    Manifest(["k1"], 1, 1, 1).save(RunDir(app.s.state_dir, "t").manifest_path)
    (app.s.data_dir / "reference.json").write_text(
        json.dumps({"titles": [{"key": "k1", "titles": ["Alpha"]}]})
    )
    cand = Candidate("suwayomi:1", "Slow", "en", "suwayomi", "https://slow.test")
    start = time.monotonic()
    assert app.cmd_run("t", [cand], 1.0, 4) == MORE_WORK
    assert time.monotonic() - start < 1.0
    state = RunDir(app.s.state_dir, "t").source(cand.id)
    assert state.titles == {}
    assert state.aborted is None  # a budget stop is not "unavailable"
    assert SUWA in app.s.suwayomi.url
