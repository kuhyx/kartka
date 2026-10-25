# Copyright (c) 2026 Krzysztof Rudnicki
"""Minimal HTTP value types plus a ``requests``-backed transport.

Everything above this module talks to a :class:`Transport`, so tests swap in a
scripted fake and never touch the network.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import threading
import time
from typing import Protocol, cast
lazy from collections.abc import Callable, Mapping

import requests
from requests.adapters import HTTPAdapter

from source_eval.models import SourceError


class TransportError(SourceError):
    """The request never produced an HTTP response (DNS, TLS, timeout...)."""


class TransportTimeoutError(TransportError):
    """No complete response within the request's timeout."""


@dataclass(frozen=True, slots=True)
class Request:
    """One HTTP request."""

    method: str
    url: str
    headers: Mapping[str, str] = field(default_factory=dict)
    body: bytes | None = None
    timeout: float = 15.0


@dataclass(frozen=True, slots=True)
class Response:
    """One HTTP response; header names are lower-case."""

    status: int
    headers: Mapping[str, str]
    body: bytes
    elapsed_ms: float

    def text(self) -> str:
        """Body decoded as UTF-8, replacing undecodable bytes."""
        return self.body.decode("utf-8", errors="replace")

    def json(self) -> object:
        """Body parsed as JSON."""
        return json.loads(self.body)


class Transport(Protocol):
    """Sends one request and returns its response."""

    def send(self, request: Request) -> Response:
        """Send ``request``; raise :class:`TransportError` on network failure."""
        ...


class Clock(Protocol):
    """Wall clock with an injectable sleep."""

    def now(self) -> float:
        """Seconds since the epoch."""
        ...

    def sleep(self, seconds: float) -> None:
        """Block for ``seconds``."""
        ...


class SystemClock:
    """The real clock."""

    def now(self) -> float:
        """Seconds since the epoch."""
        return time.time()

    def sleep(self, seconds: float) -> None:
        """Block for ``seconds`` (negative means no wait)."""
        if seconds > 0:
            time.sleep(seconds)


class _Session(Protocol):
    def request(self, method: str, url: str, **kwargs: object) -> requests.Response: ...


class RequestsTransport:
    """:class:`Transport` over a pooled ``requests`` session."""

    def __init__(self, session: _Session | None = None, pool: int = 10) -> None:
        """Wrap ``session`` (a fresh one, keeping ``pool`` connections per host).

        Every Suwayomi request goes to one host (the eval server), so the pool
        must be as large as the number of concurrent lanes, or urllib3 opens
        and discards a connection per request.
        """
        if session is None:
            fresh = requests.Session()
            adapter = HTTPAdapter(pool_connections=pool, pool_maxsize=pool)
            fresh.mount("http://", adapter)
            fresh.mount("https://", adapter)
            session = cast("_Session", fresh)
        self._session: _Session = session

    def send(self, request: Request) -> Response:
        """Send ``request``, timing it."""
        start = time.perf_counter()
        try:
            raw = self._session.request(
                request.method,
                request.url,
                headers=dict(request.headers),
                data=request.body,
                timeout=request.timeout,
            )
        except requests.Timeout as exc:
            raise TransportTimeoutError(str(exc)) from exc
        except requests.RequestException as exc:
            raise TransportError(str(exc)) from exc
        elapsed = (time.perf_counter() - start) * 1000.0
        headers = {k.lower(): v for k, v in raw.headers.items()}
        return Response(raw.status_code, headers, raw.content, elapsed)


def bounded[T](work: Callable[[], T], seconds: float) -> T:
    """``work()``, or :class:`TransportTimeoutError` once ``seconds`` have passed.

    It runs on a daemon thread that is abandoned (and dies with the process)
    on timeout, so no blocking call can outlive its budget.
    """
    box: list[T | BaseException] = []

    def run() -> None:
        try:
            box.append(work())
        except Exception as exc:  # noqa: BLE001 -- re-raised below
            box.append(exc)

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(seconds)
    if not box:
        msg = f"no response within {seconds:.1f} s"
        raise TransportTimeoutError(msg)
    if isinstance(box[0], BaseException):
        raise box[0]
    return box[0]


class BoundedTransport:
    """Caps each request's *total* wall time at its timeout.

    ``requests`` applies its timeout per socket operation, so a slow-drip
    response could outlive it; :func:`bounded` cannot be outlived.
    """

    def __init__(self, inner: Transport) -> None:
        """Bound every send of ``inner``."""
        self._inner = inner

    def send(self, request: Request) -> Response:
        """Send ``request``; :class:`TransportTimeoutError` once its timeout passes."""
        return bounded(lambda: self._inner.send(request), request.timeout)
