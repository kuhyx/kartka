# Copyright (c) 2026 Krzysztof Rudnicki
"""Paths and knobs shared by the CLI and the wiring."""

from __future__ import annotations

from dataclasses import dataclass, field
import os
from pathlib import Path

from source_eval.backends.suwayomi import SuwayomiConfig

PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _xdg(var: str, fallback: str) -> Path:
    return Path(os.environ.get(var) or Path.home() / fallback) / "kartka-source-eval"


@dataclass(frozen=True, slots=True)
class Settings:
    """Paths and knobs; every default can be overridden on the command line."""

    data_dir: Path = PACKAGE_ROOT / "data"
    out_dir: Path = PACKAGE_ROOT / "out"
    state_dir: Path = field(
        default_factory=lambda: _xdg("XDG_STATE_HOME", ".local/state")
    )
    cache_dir: Path = field(default_factory=lambda: _xdg("XDG_CACHE_HOME", ".cache"))
    interval: float = 2.0
    #: A request starts only with this much budget left (or its whole
    #: timeout, when shorter) after ``grace`` (final checkpoint + exit).
    min_start: float = 5.0
    grace: float = 1.0
    cache_ttl: float = 6 * 86400.0
    suwayomi: SuwayomiConfig = field(default_factory=SuwayomiConfig)
