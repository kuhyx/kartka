# Copyright (c) 2026 Krzysztof Rudnicki
"""The only door to the network: per-host pacing, backoff, cache, metrics.

Politeness is not optional. Every request waits for its host's slot (default
one request per 2 s, remembered on disk across runs), carries an honest
User-Agent, and backs off on 429. Cache hits are never observed, so they
cannot flatten latency or uptime statistics.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, replace
import threading
from urllib.parse import urlsplit
lazy from pathlib import Path

from source_eval.challenge import classify_http
from source_eval.fsio import read_json, write_json_atomic
from source_eval.http import Clock, Request, Response, Transport, TransportError
lazy from source_eval.cache import DiskCache

_TOO_MANY = 429
_ERROR_FLOOR = 400


@dataclass(frozen=True, slots=True)
class Observation:
    """What one live request told us about a host."""

    at: float
    host: str
    ok: bool
    ms: float
    kind: str | None
    status: int | None

    @classmethod
    def failure(cls, at: float, host: str, kind: str | None = None) -> Observation:
        """A request that never got a response."""
        return cls(at, host, ok=False, ms=0.0, kind=kind, status=None)


class HostGate:
    """Spaces requests to the same host at least ``interval`` seconds apart."""

    def __init__(self, path: Path | None, interval: float, clock: Clock) -> None:
        """Load the last-request times persisted at ``path`` (if any)."""
        self._path = path
        self._interval = interval
        self._clock = clock
        loaded = read_json(path, {}) if path is not None else {}
        self._last: dict[str, float] = dict(loaded) if isinstance(loaded, dict) else {}
        self._lock = threading.Lock()
        self._host_locks: dict[str, threading.Lock] = {}

    def wait(self, host: str) -> None:
        """Block until ``host`` may be contacted, then claim the slot."""
        with self._lock:
            host_lock = self._host_locks.setdefault(host, threading.Lock())
        with host_lock:
            delay = (
                self._last.get(host, float("-inf")) + self._interval - self._clock.now()
            )
            if delay > 0:
                self._clock.sleep(delay)
            with self._lock:
                self._last[host] = self._clock.now()
                if self._path is not None:
                    write_json_atomic(self._path, self._last)


Judge = Callable[[Response], tuple[bool, str | None]]


def judge_http(response: Response) -> tuple[bool, str | None]:
    """Default judge: an HTTP error or a challenge page is a failure."""
    kind = classify_http(response)
    return response.status < _ERROR_FLOOR and kind is None, kind


def _retry_after(response: Response, attempt: int) -> float:
    try:
        return float(str(response.headers.get("retry-after", "")))
    except ValueError:
        return 2.0 * (1 << attempt)


class PoliteClient:
    """Fetches through the gate, observing every live response."""

    def __init__(  # noqa: PLR0913 -- all collaborators are injected for tests
        self,
        transport: Transport,
        gate: HostGate,
        clock: Clock,
        cache: DiskCache | None,
        user_agent: str,
        *,
        observe: Callable[[Observation], None] | None = None,
        max_retries: int = 2,
        max_backoff: float = 20.0,
    ) -> None:
        """Wire the collaborators."""
        self._transport = transport
        self._gate = gate
        self._clock = clock
        self._cache = cache
        self._ua = user_agent
        self.observe = observe
        self._max_retries = max_retries
        self._max_backoff = max_backoff

    def _emit(self, obs: Observation) -> None:
        if self.observe is not None:
            self.observe(obs)

    def fetch(
        self,
        request: Request,
        *,
        host: str | None = None,
        cacheable: bool = False,
        judge: Judge | None = None,
        record: bool = True,
    ) -> Response:
        """Send ``request`` politely.

        Args:
            request: What to send.
            host: Pacing/metrics key; defaults to the URL's host.
            cacheable: Serve from / store in the disk cache.
            judge: Maps a response to ``(ok, challenge kind)``; the default
                reads HTTP status and challenge markers.
            record: Emit an observation (off for housekeeping calls such as
                installing an extension, which say nothing about the source).
        """
        key = host or urlsplit(request.url).hostname or request.url
        cache = self._cache if cacheable else None
        if cache is not None and (hit := cache.get(request)) is not None:
            return hit
        request = replace(request, headers={**request.headers, "User-Agent": self._ua})
        attempt = 0
        while True:
            self._gate.wait(key)
            try:
                response = self._transport.send(request)
            except TransportError:
                if record:
                    self._emit(Observation.failure(self._clock.now(), key))
                raise
            ok, kind = (judge or judge_http)(response)
            if record:
                obs = Observation(
                    self._clock.now(),
                    key,
                    ok,
                    response.elapsed_ms,
                    kind,
                    response.status,
                )
                self._emit(obs)
            if response.status == _TOO_MANY and attempt < self._max_retries:
                self._clock.sleep(
                    min(self._max_backoff, _retry_after(response, attempt))
                )
                attempt += 1
                continue
            if cache is not None and ok:
                cache.put(request, response)
            return response
