# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

lazy from pathlib import Path

import pytest
import requests

from source_eval.cache import DiskCache
from source_eval.gate import HostGate
from source_eval.http import Request, RequestsTransport, SystemClock, TransportError
from source_eval.polite import Observation, PoliteClient
from tests.fakes import FakeClock, FakeTransport, resp

UA = "kartka-source-eval/test"


def make(
    tmp_path: Path, transport: FakeTransport, clock: FakeClock
) -> tuple[PoliteClient, list[Observation]]:
    seen: list[Observation] = []
    gate = HostGate(tmp_path / "hosts.json", 2.0, clock)
    cache = DiskCache(tmp_path / "cache", 3600.0, clock)
    client = PoliteClient(transport, gate, clock, cache, UA, observe=seen.append)
    return client, seen


def test_rate_limit_per_host_and_user_agent(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(200, "x"))
    t.add("https://b.test/", resp(200, "y"))
    client, seen = make(tmp_path, t, clock)
    client.fetch(Request("GET", "https://a.test/1"))
    client.fetch(Request("GET", "https://b.test/1"))
    client.fetch(Request("GET", "https://a.test/2"))
    assert clock.slept == [2.0]
    assert all(r.headers["User-Agent"] == UA for r in t.sent)
    assert [o.ok for o in seen] == [True, True, True]


def test_gate_persists_across_instances(tmp_path: Path) -> None:
    clock = FakeClock()
    HostGate(tmp_path / "h.json", 2.0, clock).wait("a.test")
    clock.advance(0.5)
    again = HostGate(tmp_path / "h.json", 2.0, clock)
    again.wait("a.test")
    assert clock.slept == [1.5]


def test_gate_without_file(tmp_path: Path) -> None:
    clock = FakeClock()
    gate = HostGate(None, 2.0, clock)
    gate.wait("a")
    gate.wait("a")
    assert clock.slept == [2.0]


def test_backoff_on_429_then_success(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(
        "https://a.test/",
        resp(429, "slow", {"retry-after": "7"}),
        resp(429, "slow", {"retry-after": "junk"}),
        resp(200, "ok"),
    )
    client, seen = make(tmp_path, t, clock)
    out = client.fetch(Request("GET", "https://a.test/x"))
    assert out.status == 200
    assert 7.0 in clock.slept
    assert 4.0 in clock.slept
    assert [o.kind for o in seen] == ["429", "429", None]


def test_429_gives_up_after_retries(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(429, "no", {"retry-after": "999"}))
    client, _ = make(tmp_path, t, clock)
    assert client.fetch(Request("GET", "https://a.test/x")).status == 429
    assert max(clock.slept) == 20.0


def test_cache_hit_is_not_observed(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(200, "body"))
    client, seen = make(tmp_path, t, clock)
    req = Request("POST", "https://a.test/q", body=b"{}")
    first = client.fetch(req, cacheable=True)
    second = client.fetch(req, cacheable=True)
    assert first.body == second.body == b"body"
    assert len(t.sent) == 1
    assert len(seen) == 1


def test_cache_expiry_and_limits(tmp_path: Path) -> None:
    clock = FakeClock()
    cache = DiskCache(tmp_path, 10.0, clock)
    req = Request("GET", "https://a.test/")
    cache.put(req, resp(500, "err"))
    cache.put(Request("GET", "https://a.test/big"), resp(200, b"x" * (3 << 20)))
    assert cache.get(req) is None
    assert cache.get(Request("GET", "https://a.test/big")) is None
    cache.put(req, resp(200, "ok"))
    assert cache.get(req) is not None
    clock.advance(11)
    assert cache.get(req) is None


def test_transport_error_is_observed_and_raised(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", TransportError("boom"))
    client, seen = make(tmp_path, t, clock)
    with pytest.raises(TransportError):
        client.fetch(Request("GET", "https://a.test/x"), host="custom")
    assert seen[0] == Observation(
        clock.now(), "custom", ok=False, ms=0.0, kind=None, status=None
    )


def test_no_observer_no_cache(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add("https://a.test/", resp(403, "denied"))
    client = PoliteClient(t, HostGate(None, 2.0, clock), clock, None, UA)
    assert client.fetch(Request("GET", "https://a.test/"), cacheable=True).status == 403


class _Sess:
    def __init__(self, fail: bool) -> None:
        self.fail = fail

    def request(self, method: str, url: str, **kw: object) -> requests.Response:
        if self.fail:
            msg = "down"
            raise requests.ConnectionError(msg)
        r = requests.Response()
        r.status_code = 201
        r._content = b"hi"
        r.headers["X-A"] = "1"
        return r


def test_requests_transport() -> None:
    out = RequestsTransport(_Sess(fail=False)).send(Request("GET", "https://x/"))
    assert (out.status, out.body, out.headers["x-a"]) == (201, b"hi", "1")
    assert out.text() == "hi"
    with pytest.raises(TransportError):
        RequestsTransport(_Sess(fail=True)).send(Request("GET", "https://x/"))
    assert isinstance(RequestsTransport().send, object)


def test_system_clock(monkeypatch: pytest.MonkeyPatch) -> None:
    slept: list[float] = []
    monkeypatch.setattr("source_eval.http.time.sleep", slept.append)
    clock = SystemClock()
    assert clock.now() > 0
    clock.sleep(0.25)
    clock.sleep(-1)
    assert slept == [0.25]
