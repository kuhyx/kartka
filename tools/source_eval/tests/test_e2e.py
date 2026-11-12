# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
from pathlib import Path

from crdt_sync import E2eKey
import pytest

from source_eval import e2e
from source_eval.e2e import HEADER, E2eLockedError, open_cipher, open_node
from tests.e2e_support import CIPHER, HEADER_TEXT, PASSPHRASE, seal

VECTORS = Path(__file__).parents[3] / "test" / "fixtures" / "e2e_vectors.json"


class Db:
    def __init__(self, header: object = HEADER_TEXT) -> None:
        self.header = header
        self.patches: list[tuple[str, dict[str, object]]] = []

    def get(self, path: str) -> object:
        assert path == HEADER
        return self.header

    def patch(self, path: str, data: dict[str, object]) -> None:
        self.patches.append((path, data))


def test_the_apps_vectors_open() -> None:
    """Sealed by the Dart app (test/sync/e2e/e2e_vectors_test.dart)."""
    vectors = json.loads(VECTORS.read_text(encoding="utf-8"))
    key = E2eKey.from_bytes(bytes.fromhex(vectors["key"]))
    cipher = key.cipher(accept_plaintext=False)
    for case in vectors["nodes"]:
        assert open_node(cipher, case["path"], case["stored"]) == case["node"]
        assert open_node(cipher, f"{case['path']}x", case["stored"]) is None


def test_the_password_file(password_file: Path) -> None:
    assert e2e.read_passphrase() == PASSPHRASE
    password_file.unlink()
    assert e2e.read_passphrase() == ""


@pytest.mark.parametrize(
    ("header", "secret", "why"),
    [
        (HEADER_TEXT, "", "no crdt-sync password"),
        (HEADER_TEXT, "wrong", "wrong"),
        ({"not": "a header"}, PASSPHRASE, "unreadable"),
    ],
)
def test_locked(header: object, secret: str, why: str) -> None:
    with pytest.raises(E2eLockedError, match=why):
        open_cipher(Db(header), lambda: secret)


def test_opens_with_the_right_password() -> None:
    cipher = open_cipher(Db(), lambda: PASSPHRASE)
    assert cipher is not None
    stored = seal("settings/k", {"key": "k"})
    assert open_node(cipher, "settings/k", stored) == {"key": "k"}
    assert open_cipher(Db(None), lambda: PASSPHRASE) is None


def test_clear_fields_are_bound() -> None:
    stored = seal("settings/k", {"key": "k"}, newest="2026-01-01T00:00:00.000Z-0000-a")
    assert open_node(CIPHER, "settings/k", stored) == {"key": "k"}
    assert open_node(CIPHER, "settings/k", {**stored, "d": True}) is None
    assert open_node(CIPHER, "settings/k", {**stored, "h": 3}) is None
    assert open_node(CIPHER, "settings/k", seal("settings/k", [1])) is None


def test_the_header_store() -> None:
    db = Db()
    store = e2e._HeaderStore(db)
    with pytest.raises(E2eLockedError):
        store.put_file_text(HEADER, HEADER_TEXT, message="m")
    assert db.patches == []
    assert store.list_directory("kartka-e2e") == []
    assert store.can_access_remote()
    with pytest.raises(E2eLockedError):
        store.delete_file(HEADER)
