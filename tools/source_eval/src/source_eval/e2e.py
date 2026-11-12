# Copyright (c) 2026 Krzysztof Rudnicki
"""Opening the app's sealed RTDB nodes (``lib/sync/e2e/sealed_transport.dart``).

Since end-to-end encryption the app's data lives under ``/kartka-e2e``;
every node is ``{"p": <sealed JSON>, "h": <newest Hlc>, "d": true?}``, the
blob crdt_sync's ``E2eCipher`` with AAD ``kartka-e2e/<path>#<d>#<h>`` under
the Argon2id key of the shared crdt-sync password (header at
``kartka-e2e/e2e``). ``tools/errors/src/kartka_errors/e2e.py`` is the
same module for the error collector (separate package); both are pinned to
the app by ``test/fixtures/e2e_vectors.json``.
"""

from __future__ import annotations

import json
from typing import Final, Protocol
lazy from collections.abc import Callable

from crdt_sync import (
    PASSWORD_FILE,
    E2eCipher,
    E2eDecryptError,
    E2eHeaderError,
    E2eWrongPassphraseError,
    unlock_e2e,
)

ROOT: Final = "kartka-e2e"
HEADER: Final = f"{ROOT}/e2e"


class E2eLockedError(RuntimeError):
    """No (right) passphrase, or an unreadable header: nothing may be read."""


class _Reader(Protocol):
    def get(self, path: str) -> object: ...


class _HeaderStore:
    """crdt_sync's ``RemoteStore``, just enough for ``unlock_e2e``: read-only.

    Only the app creates the header; :func:`open_cipher` never unlocks
    without one, so ``put_file_text`` is unreachable and refuses.
    """

    def __init__(self, rtdb: _Reader) -> None:
        self._rtdb = rtdb

    def get_file_text(self, path: str) -> str | None:
        value = self._rtdb.get(path)
        return value if value is None or isinstance(value, str) else json.dumps(value)

    def put_file_text(self, path: str, text: str, *, message: str) -> None:
        del text, message
        msg = f"PC tools never write the e2e header ({path})"
        raise E2eLockedError(msg)

    def list_directory(self, path: str) -> list[str]:
        del path
        return []

    def delete_file(self, path: str, *, message: str = "") -> None:
        del message
        msg = f"the e2e header is never deleted ({path})"
        raise E2eLockedError(msg)

    def can_access_remote(self) -> bool:
        return True


def read_passphrase() -> str:
    """The shared crdt-sync password (``~/.config/crdt-sync/password``)."""
    try:
        return str(PASSWORD_FILE.read_text(encoding="utf-8")).strip()
    except OSError:
        return ""


def open_cipher(rtdb: _Reader, passphrase: Callable[[], str]) -> E2eCipher | None:
    """The app's cipher; None while no app has sealed anything (no header).

    Raises:
        E2eLockedError: No passphrase, a wrong one, or an unreadable header.
    """
    if rtdb.get(HEADER) is None:
        return None
    secret = passphrase()
    if not secret:
        msg = "no crdt-sync password on this PC"
        raise E2eLockedError(msg)
    try:
        key = unlock_e2e(
            _HeaderStore(rtdb), path_prefix=ROOT, passphrase=secret, e2e_path=HEADER
        )
    except E2eWrongPassphraseError:
        msg = "wrong crdt-sync password"
        raise E2eLockedError(msg) from None
    except E2eHeaderError:
        msg = "unreadable e2e header"
        raise E2eLockedError(msg) from None
    return key.cipher(accept_plaintext=False)


def node_aad(rel: str, stored: dict[str, object]) -> str:
    """The AAD of the node stored at ``rel`` (relative to :data:`ROOT`)."""
    deleted = 1 if stored.get("d") is True else 0
    newest = stored.get("h")
    return f"{ROOT}/{rel}#{deleted}#{newest if isinstance(newest, str) else ''}"


def open_node(cipher: E2eCipher, rel: str, stored: object) -> dict[str, object] | None:
    """The node stored at ``rel``, or None when it does not open."""
    if not isinstance(stored, dict) or not isinstance(stored.get("p"), str):
        return None
    newest = stored.get("h")
    if newest is not None and not isinstance(newest, str):
        return None
    try:
        node = json.loads(cipher.open(stored["p"], path=node_aad(rel, stored)))
    except E2eDecryptError, ValueError:
        return None
    return node if isinstance(node, dict) else None
