# Copyright (c) 2026 Krzysztof Rudnicki
"""A test key and sealing as the app does it (``sealed_transport.dart``)."""

from __future__ import annotations

import json

from crdt_sync import Argon2Params, unlock_e2e

from source_eval.e2e import HEADER, ROOT, node_aad

PASSPHRASE = "test-passphrase"  # noqa: S105 -- a throwaway test secret
FAST = Argon2Params(memory_kib=8, iterations=1, parallelism=1)


class MemStore:
    """An in-memory ``RemoteStore`` holding just the header."""

    def __init__(self) -> None:
        self.files: dict[str, str] = {}

    def get_file_text(self, path: str) -> str | None:
        return self.files.get(path)

    def put_file_text(self, path: str, text: str, *, message: str) -> None:
        self.files[path] = text

    def list_directory(self, path: str) -> list[str]:
        return []

    def delete_file(self, path: str, *, message: str = "") -> None:
        self.files.pop(path, None)

    def can_access_remote(self) -> bool:
        return True


_store = MemStore()
CIPHER = unlock_e2e(
    _store, path_prefix=ROOT, passphrase=PASSPHRASE, params=FAST, e2e_path=HEADER
).cipher(accept_plaintext=False)
HEADER_TEXT = _store.files[HEADER]


def seal(rel: str, node: object, *, newest: str | None = None) -> dict[str, object]:
    """``node`` stored at ``rel`` as the app stores it."""
    stored: dict[str, object] = {} if newest is None else {"h": newest}
    stored["p"] = CIPHER.seal(json.dumps(node), path=node_aad(rel, stored))
    return stored
