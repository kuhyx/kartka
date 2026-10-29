# Copyright (c) 2026 Krzysztof Rudnicki
"""A minimal RTDB REST client on the evaluator's seeded Google session.

The sync account is Google-only, so there is no password sign-in: the
session is ``~/.config/kartka-source-eval/firebase_auth.json``, the one
``tools/source_eval`` already uses (crdt-sync's ``tool.seed_session``
writes it once, then it refreshes itself). The request URL carries the ID
token (``?auth=``), so no error raised here ever includes it.
"""

from __future__ import annotations

from collections.abc import Callable
import json
from typing import Protocol
import urllib.error
import urllib.request

import crdt_sync

#: The credential store reused from the source evaluator.
APP_NAME = "kartka-source-eval"
#: Per-request timeout, seconds (token refresh has its own, below).
TIMEOUT = 15.0
TOKEN_TIMEOUT = 8.0
SEED_HINT = (
    "no kartka-source-eval sign-in session; seed one with: cd ~/src/utils/"
    "crdt-sync && python3 -m tool.seed_session --app kartka-source-eval"
    " (full command: SEED_CMD in tools/agent/lib.sh)"
)

type Opener = Callable[..., object]


class NoSessionError(RuntimeError):
    """There is no seeded sign-in session."""


class RtdbError(RuntimeError):
    """An RTDB request failed (the message never names the URL)."""


class Rtdb(Protocol):
    """Read and multi-path write access to RTDB."""

    def get(self, path: str) -> object:
        """The decoded JSON at ``path`` (None when absent)."""
        ...

    def patch(self, path: str, data: dict[str, object]) -> None:
        """Multi-path update of ``path`` (a None value deletes)."""
        ...


class RestRtdb:
    """RTDB over REST with ``?auth=<id token>``."""

    def __init__(
        self,
        database_url: str,
        id_token: Callable[[], str],
        opener: Opener = urllib.request.urlopen,
    ) -> None:
        """Talk to ``database_url`` with tokens from ``id_token``."""
        self._url = database_url.rstrip("/")
        self._id_token = id_token
        self._open = opener

    def _send(self, method: str, path: str, body: bytes | None) -> object:
        try:
            token = self._id_token()
        except Exception as e:  # noqa: BLE001 -- any refresh failure, typed only
            msg = f"RTDB {method} {path}: token refresh failed ({type(e).__name__})"
            raise RtdbError(msg) from None
        req = urllib.request.Request(  # noqa: S310 -- https only, built here
            f"{self._url}/{path}.json?auth={token}",
            data=body,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        try:
            with self._open(req, timeout=TIMEOUT) as res:  # type: ignore[attr-defined]
                return json.loads(res.read() or b"null")
        except urllib.error.HTTPError as e:
            msg = f"RTDB {method} {path}: HTTP {e.code}"
            raise RtdbError(msg) from None
        except (urllib.error.URLError, OSError, ValueError) as e:
            msg = f"RTDB {method} {path}: {type(e).__name__}"
            raise RtdbError(msg) from None

    def get(self, path: str) -> object:
        """GET ``path``; raises :class:`RtdbError` on any failure."""
        return self._send("GET", path, None)

    def patch(self, path: str, data: dict[str, object]) -> None:
        """PATCH ``data`` into ``path``; raises :class:`RtdbError`."""
        self._send("PATCH", path, json.dumps(data).encode())


def open_rtdb() -> RestRtdb:
    """The client on the seeded session; :class:`NoSessionError` without one."""
    config = crdt_sync.FirebaseConfig.load()
    store = crdt_sync.credential_store_for(APP_NAME)
    auth = crdt_sync.FirebaseTokenProvider(
        config.api_key, store, timeout_seconds=TOKEN_TIMEOUT
    )
    if not auth.has_session():
        raise NoSessionError(SEED_HINT)
    return RestRtdb(config.database_url, auth.id_token)
