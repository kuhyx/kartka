# Copyright (c) 2026 Krzysztof Rudnicki
"""Shared fixtures."""

from __future__ import annotations

import pytest

from source_eval import rejected


@pytest.fixture
def no_rejects(monkeypatch: pytest.MonkeyPatch) -> None:
    """No score rejects: for tests whose weak fake sources must stay reported."""
    monkeypatch.setattr(rejected, "REJECT_SCORE", -1.0)
