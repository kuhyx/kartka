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
from urllib.parse import urlsplit
lazy import threading

from source_eval.budget import BudgetExhausted, RequestBudget
from source_eval.challenge import classify_http
from source_eval.gate import take
from source_eval.http import (
    Clock,
    Request,
    Response,
    Transport,
    TransportError,
    TransportTimeoutError,
)
lazy from source_eval.cache import DiskCache
lazy from source_eval.gate import HostGate

USER_AGENT = (
    "kartka-source-eval/0.1 (+https://github.com/kuhyx/kartka; polite: 1 req/2s/host)"
)
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
    """Fetches through the gate, observing every live response.

    With a ``budget`` every wait (gate slot, in-flight slot, 429 backoff) and
    every request fits in what is left of the invocation. ``inflight`` caps
    concurrent requests (the eval server queues the rest internally, which
    would inflate the latency it reports for the source).
    """

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
        budget: RequestBudget | None = None,
        inflight: threading.Semaphore | None = None,
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
        self._budget = budget or RequestBudget(None)
        self._inflight = inflight

    def _emit(self, obs: Observation) -> None:
        if self.observe is not None:
            self.observe(obs)

    def _start(self, key: str, *, paced: bool) -> None:
        """Wait for the host's slot (when paced) and an in-flight slot."""
        latest = self._budget.latest_start()
        if paced:
            self._gate.wait(key, latest, self._inflight)
        elif self._inflight is not None:
            take(self._inflight, latest, self._clock)

    def _send(self, request: Request) -> Response:
        """Send within the budget, then free the in-flight slot.

        A timeout the budget shortened is the budget's (BudgetExhausted); the
        request's own full timeout is the source's failure.
        """
        slot = self._inflight
        try:
            timeout = self._budget.timeout(request.timeout)
            try:
                return self._transport.send(replace(request, timeout=timeout))
            except TransportTimeoutError:
                if timeout < request.timeout:
                    raise BudgetExhausted from None
                raise
        finally:
            if slot is not None:
                slot.release()

    def _backoff(self, response: Response, attempt: int) -> None:
        pause = min(self._max_backoff, _retry_after(response, attempt))
        latest = self._budget.latest_start()
        if latest is not None and self._clock.now() + pause > latest:
            raise BudgetExhausted
        self._clock.sleep(pause)

    def fetch(  # noqa: PLR0913 -- keyword knobs of one call
        self,
        request: Request,
        *,
        host: str | None = None,
        cacheable: bool = False,
        judge: Judge | None = None,
        record: bool = True,
        paced: bool = True,
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
            paced: Wait for the host's slot. Only a purely local lookup on
                the eval server (no third-party host behind it) skips it.

        Raises:
            BudgetExhausted: The budget cannot fit this request (or its
                timeout, shortened to fit, ran out): nothing is observed.
        """
        key = host or urlsplit(request.url).hostname or request.url
        cache = self._cache if cacheable else None
        if cache is not None and (hit := cache.get(request)) is not None:
            return hit
        request = replace(request, headers={**request.headers, "User-Agent": self._ua})
        attempt = 0
        while True:
            self._start(key, paced=paced)
            try:
                response = self._send(request)
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
                self._backoff(response, attempt)
                attempt += 1
                continue
            if cache is not None and ok:
                cache.put(request, response)
            return response
