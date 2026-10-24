# Copyright (c) 2026 Krzysztof Rudnicki
"""Crash-safe JSON files: a run can be killed mid-write and still resume."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile


def write_json_atomic(path: Path, data: object) -> None:
    """Write ``data`` to ``path`` via a temp file and an atomic rename."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=1, sort_keys=True)
        handle.write("\n")
    Path(tmp).replace(path)


def read_json(path: Path, default: object = None) -> object:
    """Return the parsed JSON at ``path``, or ``default`` if it is missing."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
