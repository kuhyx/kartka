"""Minimal HTTP value types plus a ``requests``-backed transport.

Everything above this module talks to a :class:`Transport`, so tests swap in a
scripted fake and never touch the network.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
import json
import time
from typing import Protocol

import requests

from source_eval.models import SourceError


class TransportError(SourceError):
    """The request never produced an HTTP response (DNS, TLS, timeout...)."""


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

    def __init__(self, session: _Session | None = None) -> None:
        """Wrap ``session`` (a fresh ``requests.Session`` by default)."""
        self._session: _Session = session if session is not None else requests.Session()

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
        except requests.RequestException as exc:
            raise TransportError(str(exc)) from exc
        elapsed = (time.perf_counter() - start) * 1000.0
        headers = {k.lower(): v for k, v in raw.headers.items()}
        return Response(raw.status_code, headers, raw.content, elapsed)
