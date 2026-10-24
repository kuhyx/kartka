"""Test doubles: a fake clock that never sleeps and a scripted transport."""

from __future__ import annotations

from collections.abc import Callable
import json
from pathlib import Path

from source_eval.http import Request, Response, TransportError

FIXTURES = Path(__file__).parent / "fixtures"


def fixture_bytes(name: str) -> bytes:
    """Return the raw bytes of a recorded fixture."""
    return (FIXTURES / name).read_bytes()


def fixture_json(name: str) -> object:
    """Return a recorded JSON fixture, parsed."""
    return json.loads(fixture_bytes(name))


class FakeClock:
    """Wall clock that advances only when ``sleep`` or ``advance`` is called."""

    def __init__(self, start: float = 1_800_000_000.0) -> None:
        self.t = start
        self.slept: list[float] = []

    def now(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.slept.append(seconds)
        self.t += seconds

    def advance(self, seconds: float) -> None:
        self.t += seconds


def resp(
    status: int = 200,
    body: bytes | str | object = b"",
    headers: dict[str, str] | None = None,
    elapsed_ms: float = 100.0,
) -> Response:
    """Build a response; dicts/lists are JSON-encoded."""
    if isinstance(body, str):
        raw = body.encode()
    elif isinstance(body, bytes):
        raw = body
    else:
        raw = json.dumps(body).encode()
    return Response(status, dict(headers or {}), raw, elapsed_ms)


Handler = Callable[[Request], Response]


class FakeTransport:
    """Routes requests by URL prefix to queued responses or handlers."""

    def __init__(self) -> None:
        self.routes: list[tuple[str, list[Response | Handler | Exception]]] = []
        self.sent: list[Request] = []

    def add(self, prefix: str, *items: Response | Handler | Exception) -> None:
        self.routes.append((prefix, list(items)))

    def send(self, request: Request) -> Response:
        self.sent.append(request)
        for prefix, items in self.routes:
            if request.url.startswith(prefix) and items:
                item = items[0] if len(items) == 1 else items.pop(0)
                if isinstance(item, Exception):
                    raise item
                if isinstance(item, Response):
                    return item
                return item(request)
        msg = f"no route for {request.url}"
        raise TransportError(msg)
