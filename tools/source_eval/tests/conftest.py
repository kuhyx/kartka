# Copyright (c) 2026 Krzysztof Rudnicki
"""Every test reads a throwaway crdt-sync password, never the real one."""

from __future__ import annotations

lazy from pathlib import Path

import pytest

from source_eval import e2e
from tests.e2e_support import PASSPHRASE


@pytest.fixture(autouse=True)
def password_file(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    path = tmp_path / "crdt-sync-password"
    path.write_text(f"{PASSPHRASE}\n", encoding="utf-8")
    monkeypatch.setattr(e2e, "PASSWORD_FILE", path)
    return path
