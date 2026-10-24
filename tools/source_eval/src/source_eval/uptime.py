# Copyright (c) 2026 Krzysztof Rudnicki
"""Uptime probes, 4x a day, kept as JSON lines per source.

A measurable source is probed the way Kartka reads it: one uncached
"popular, page 1" call through its backend. A source with no backend yet
(plugin candidates) falls back to one GET of its front page. A host this
machine's own hosts-file blocklist points at 0.0.0.0 is recorded as
``hosts-blocked`` and left out of every metric: that says nothing about the
site.
"""

from __future__ import annotations

from collections.abc import Callable
import json
import socket
from typing import TYPE_CHECKING

from source_eval.http import Request, TransportError
from source_eval.polite import Observation, judge_http
from source_eval.state import sha1

if TYPE_CHECKING:
    from pathlib import Path

    from source_eval.http import Clock
    from source_eval.polite import PoliteClient

WINDOW_DAYS = 7
HOSTS_BLOCKED = "hosts-blocked"
_DAY = 86400.0
#: A window counts as ``final`` once probes span this much of it.
_FINAL_SPAN = WINDOW_DAYS * _DAY - 6 * 3600.0
_NULL_ADDRS = frozenset({"0.0.0.0", "::", "127.0.0.1", "::1"})  # noqa: S104 -- compared, not bound

Resolver = Callable[[str], list[str]]


def resolve(host: str) -> list[str]:
    """Every address ``host`` resolves to here ([] when it does not)."""
    try:
        return sorted({str(info[4][0]) for info in socket.getaddrinfo(host, 443)})
    except OSError:
        return []


def locally_blocked(host: str, resolver: Resolver = resolve) -> bool:
    """True when the local resolver sinks ``host`` (hosts-file blocklist)."""
    addrs = resolver(host)
    return bool(addrs) and all(a in _NULL_ADDRS for a in addrs)


class UptimeLog:
    """Append-only probe history, one file per source id."""

    def __init__(self, root: Path) -> None:
        """Store histories under ``root``."""
        self.root = root

    def _path(self, key: str) -> Path:
        return self.root / f"{sha1(key)}.jsonl"

    def append(self, key: str, obs: Observation) -> None:
        """Record one probe of ``key``."""
        self.root.mkdir(parents=True, exist_ok=True)
        line = {
            "at": obs.at,
            "host": obs.host,
            "ok": obs.ok,
            "ms": round(obs.ms, 1),
            "kind": obs.kind,
            "status": obs.status,
        }
        with self._path(key).open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(line) + "\n")

    def _all(self, key: str) -> list[Observation]:
        path = self._path(key)
        if not path.exists():
            return []
        rows = [
            json.loads(raw)
            for raw in path.read_text(encoding="utf-8").splitlines()
            if raw
        ]
        return [
            Observation(d["at"], d["host"], d["ok"], d["ms"], d["kind"], d["status"])
            for d in rows
        ]

    def window(self, key: str, now: float) -> list[Observation]:
        """Usable probes of ``key`` within the last :data:`WINDOW_DAYS` days."""
        return [
            o
            for o in self._all(key)
            if now - o.at <= WINDOW_DAYS * _DAY and o.kind != HOSTS_BLOCKED
        ]

    def last(self, key: str) -> Observation | None:
        """The most recent probe of ``key``, blocked or not."""
        probes = self._all(key)
        return probes[-1] if probes else None


def summarize(probes: list[Observation], now: float) -> dict[str, object]:
    """Contract ``uptime`` block."""
    ok = sum(1 for p in probes if p.ok)
    span = now - min((p.at for p in probes), default=now)
    return {
        "windowDays": WINDOW_DAYS,
        "probes": len(probes),
        "ok": ok,
        "ratio": round(ok / len(probes), 3) if probes else None,
        "status": "final" if probes and span >= _FINAL_SPAN else "accruing",
    }


def failed(clock: Clock, host: str, resolver: Resolver = resolve) -> Observation:
    """The observation for a probe that never got a response."""
    kind = HOSTS_BLOCKED if locally_blocked(host, resolver) else None
    return Observation.failure(clock.now(), host, kind)


def probe_front_page(
    client: PoliteClient,
    clock: Clock,
    host: str,
    url: str,
    resolver: Resolver = resolve,
) -> Observation:
    """GET ``url`` once (never cached) and judge it. Thread-safe."""
    try:
        response = client.fetch(
            Request("GET", url, timeout=20.0), host=host, record=False
        )
    except TransportError:
        return failed(clock, host, resolver)
    ok, kind = judge_http(response)
    return Observation(
        clock.now(), host, ok, response.elapsed_ms, kind, response.status
    )
