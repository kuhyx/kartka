# Copyright (c) 2026 Krzysztof Rudnicki
"""On-disk response cache so a resumed run does not re-hit a site."""

from __future__ import annotations

import base64
import hashlib
lazy from pathlib import Path

from source_eval.fsio import read_json, write_json_atomic
from source_eval.http import Clock, Request, Response

_MAX_BODY = 2 << 20
_OK = 200


class DiskCache:
    """Caches successful small responses for ``ttl`` seconds."""

    def __init__(self, root: Path, ttl: float, clock: Clock) -> None:
        """Store entries under ``root``."""
        self._root = root
        self._ttl = ttl
        self._clock = clock

    def _path(self, request: Request) -> Path:
        h = hashlib.sha1(usedforsecurity=False)
        h.update(f"{request.method} {request.url}\n".encode())
        h.update(request.body or b"")
        digest = h.hexdigest()
        return self._root / digest[:2] / f"{digest}.json"

    def get(self, request: Request) -> Response | None:
        """Return the cached response for ``request`` if still fresh."""
        entry = read_json(self._path(request))
        if not isinstance(entry, dict) or self._clock.now() - entry["at"] > self._ttl:
            return None
        body = base64.b64decode(entry["body"])
        return Response(entry["status"], entry["headers"], body, 0.0)

    def put(self, request: Request, response: Response) -> None:
        """Remember ``response`` if it is a 200 under the size cap."""
        if response.status != _OK or len(response.body) > _MAX_BODY:
            return
        write_json_atomic(
            self._path(request),
            {
                "at": self._clock.now(),
                "status": response.status,
                "headers": dict(response.headers),
                "body": base64.b64encode(response.body).decode(),
            },
        )
