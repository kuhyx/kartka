# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
from pathlib import Path

from crdt_sync import E2eKey
import pytest

from kartka_errors import e2e
from kartka_errors.cli import ERRORS_PATH
from kartka_errors.e2e import HEADER, E2eLockedError, open_cipher, open_node
from tests.e2e_support import CIPHER, HEADER_TEXT, PASSPHRASE, seal
from tests.test_cli import ENTRY, FakeRtdb, run

VECTORS = Path(__file__).parents[3] / "test" / "fixtures" / "e2e_vectors.json"


def test_the_apps_vectors_open() -> None:
    """Sealed by the Dart app (test/sync/e2e/e2e_vectors_test.dart)."""
    vectors = json.loads(VECTORS.read_text(encoding="utf-8"))
    key = E2eKey.from_bytes(bytes.fromhex(vectors["key"]))
    cipher = key.cipher(accept_plaintext=False)
    for case in vectors["nodes"]:
        assert open_node(cipher, case["path"], case["stored"]) == case["node"]
        moved = f"{case['path']}x"
        assert open_node(cipher, moved, case["stored"]) is None


def test_no_header_means_nothing_sealed_yet(tmp_path: Path) -> None:
    db = FakeRtdb({"d": {"1": ENTRY}}, header=None)
    assert run(tmp_path, db, "ingest")[0] == 0
    assert db.patches == []


@pytest.mark.parametrize("secret", ["", "wrong"])
def test_locked_reads_and_deletes_nothing(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    password_file: Path,
    secret: str,
) -> None:
    password_file.write_text(secret, encoding="utf-8")
    db = FakeRtdb({"d": {"1": ENTRY}})
    assert run(tmp_path, db, "ingest")[0] == 4
    assert "e2e locked" in capsys.readouterr().err
    assert db.patches == []
    assert not (tmp_path / "state.json").exists()


def test_a_missingpassword_file_is_locked(tmp_path: Path, password_file: Path) -> None:
    password_file.unlink()
    assert e2e.read_passphrase() == ""
    assert run(tmp_path, FakeRtdb({"d": {"1": ENTRY}}), "ingest")[0] == 4


def test_an_unreadable_header_is_locked() -> None:
    with pytest.raises(E2eLockedError, match="unreadable"):
        open_cipher(FakeRtdb(None, header={"not": "a header"}), lambda: PASSPHRASE)


def test_reports_that_do_not_open_are_dropped_but_deleted(tmp_path: Path) -> None:
    db = FakeRtdb(None)
    db.tree = {
        "d": {
            "plain": ENTRY,
            "moved": seal("errors/d/other", ENTRY),
            "list": seal("errors/d/list", [1]),
            "badh": {**seal("errors/d/badh", ENTRY), "h": 3},
        }
    }
    assert run(tmp_path, db, "ingest")[0] == 0
    assert db.patches == [
        (ERRORS_PATH, dict.fromkeys(["d/plain", "d/moved", "d/list", "d/badh"]))
    ]
    state = json.loads((tmp_path / "state.json").read_text())
    assert state["seen"] == {}


def test_clear_fields_are_bound() -> None:
    stored = seal("settings/k", {"key": "k"}, newest="2026-01-01T00:00:00.000Z-0000-a")
    assert open_node(CIPHER, "settings/k", stored) == {"key": "k"}
    assert open_node(CIPHER, "settings/k", {**stored, "d": True}) is None
    assert open_node(CIPHER, "settings/k", {**stored, "h": "x"}) is None


def test_the_header_store() -> None:
    db = FakeRtdb(None)
    store = e2e._HeaderStore(db)
    with pytest.raises(E2eLockedError):
        store.put_file_text(HEADER, HEADER_TEXT, message="m")
    assert db.patches == []
    assert store.list_directory("kartka-e2e") == []
    assert store.can_access_remote()
    with pytest.raises(E2eLockedError):
        store.delete_file(HEADER)
