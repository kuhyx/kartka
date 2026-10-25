# Copyright (c) 2026 Krzysztof Rudnicki
"""Every blocking wait honours the budget: lane, gate, in-flight slot."""

from __future__ import annotations

import json
import threading
lazy from pathlib import Path

import pytest
import requests

from source_eval.app import MORE_WORK
from source_eval.budget import BudgetExhausted, Deadline, RequestBudget
from source_eval.gate import HostGate
from source_eval.http import Request, RequestsTransport, TransportTimeoutError
from source_eval.polite import PoliteClient
from source_eval.reference import anilist, mangaupdates
from source_eval.state import Manifest
from tests.app_helpers import make_app
from tests.fakes import FakeClock, FakeTransport, resp


def test_requests_timeout_is_a_transport_timeout() -> None:
    class Session:
        def request(self, method: str, url: str, **kwargs: object) -> object:
            msg = "read timed out"
            raise requests.ReadTimeout(msg)

    with pytest.raises(TransportTimeoutError, match="read timed out"):
        RequestsTransport(Session()).send(Request("GET", "https://a.test/"))  # type: ignore[arg-type]


def test_default_session_pools_one_connection_per_lane() -> None:
    transport = RequestsTransport(pool=64)
    adapter = transport._session.get_adapter("http://127.0.0.1:4590/")  # type: ignore[attr-defined]
    assert adapter._pool_maxsize == 64


def test_busy_host_lock_past_the_latest_start_refuses(tmp_path: Path) -> None:
    clock = FakeClock()
    gate = HostGate(None, 2.0, clock)
    gate.wait("a.test")
    lock = gate._host_locks["a.test"]
    lock.acquire()  # another lane is sleeping for the slot
    try:
        with pytest.raises(BudgetExhausted):
            gate.wait("a.test", latest=clock.now())
    finally:
        lock.release()


def test_no_inflight_slot_before_the_latest_start_refuses(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(200, "x"))
    budget = RequestBudget(Deadline(clock, 7.0), min_start=5.0, grace=1.0)
    full = threading.Semaphore(0)
    client = PoliteClient(
        t, HostGate(None, 2.0, clock), clock, None, "ua", budget=budget, inflight=full
    )
    with pytest.raises(BudgetExhausted):
        client.fetch(Request("GET", "https://a.test/x"))
    assert t.sent == []
    free = threading.Semaphore(1)
    unbudgeted = PoliteClient(
        t, HostGate(None, 2.0, clock), clock, None, "ua", inflight=free
    )
    assert unbudgeted.fetch(Request("GET", "https://a.test/x")).status == 200


def _throttled(app_transport: FakeTransport, prefix: str) -> None:
    app_transport.routes.insert(0, (prefix, [resp(429, "", {"retry-after": "30"})]))


def test_reference_and_enrich_stop_in_budget(tmp_path: Path) -> None:
    app, transport, _, lines = make_app(tmp_path)
    _throttled(transport, anilist.ENDPOINT)
    assert app.cmd_reference(30.0, 3) == MORE_WORK
    assert "reference: 0 titles, complete=False" in lines
    transport.routes.pop(0)
    assert app.cmd_reference(None, 3) == 0
    ref = {"titles": [{"key": "k1", "titles": ["Alpha"]}]}
    (app.s.data_dir / "reference.json").write_text(json.dumps(ref))
    app.cmd_init_run("t", 1, Manifest([], 1, 1, 1))
    _throttled(transport, mangaupdates.API)
    assert app.cmd_enrich("t", 30.0) == MORE_WORK
    assert "enrich: complete=False" in lines


def test_ramp_finish_of_another_run_says_so(tmp_path: Path) -> None:
    app, _, _, lines = make_app(tmp_path)
    assert app.cmd_ramp_finish("nope") == 0
    assert "ramp: nope is not the current run; nothing recorded" in lines
