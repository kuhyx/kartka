# Copyright (c) 2026 Krzysztof Rudnicki
"""The per-signature fields the board reads from ``state.json``."""

import json
from pathlib import Path
from typing import cast

from kartka_errors.signature import signature
from kartka_errors.state import Entry, load_state, merge, open_signatures, save_state


def err(at: str, **extra: object) -> Entry:
    base: dict[str, object] = {
        "at": at,
        "kind": "reader.open",
        "error": "FormatException: bad 42",
        "stack": ["#0 f (package:kartka/reader/x.dart:1:1)"],
        "route": "/reader/:id",
    }
    return cast("Entry", {**base, **extra})


def test_board_fields_of_an_error_record() -> None:
    state = load_state(Path("/nonexistent"))
    e = err("2026-11-17T10:00:00Z", build=410, version="0.1.0-abc")
    merge(state, "dev-a", "1", e)
    (rec,) = open_signatures(state)
    assert rec["app"] == "kartka"
    assert rec["signature"] == signature(cast("dict[str, object]", e)).id == rec["id"]
    assert rec["kind"] == "reader.open"
    assert rec["message"] == "FormatException: bad <n>"
    assert rec["top_frame"] == "f (package:kartka/reader/x.dart)"
    assert rec["first_seen"] == rec["first"] == "2026-11-17T10:00:00Z"
    assert rec["last_seen"] == rec["last"] == "2026-11-17T10:00:00Z"
    assert rec["build"] == 410
    assert rec["build_min"] == 410
    assert rec["version_name"] == "0.1.0-abc"
    assert rec["detail"] == {"routes": ["/reader/:id"], "sources": []}


def test_build_is_the_max_seen_and_min_of_each_devices_latest() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "a", "1", err("2026-11-17T10:00:00Z", build=400, version="v400"))
    merge(state, "a", "2", err("2026-11-17T11:00:00Z", build=410, version="v410"))
    merge(state, "b", "3", err("2026-11-17T11:30:00Z", build=405, version="v405"))
    merge(state, "b", "4", err("2026-11-17T09:00:00Z", build=380, version="v380"))
    (rec,) = open_signatures(state)
    assert rec["build"] == 410
    assert rec["version_name"] == "v410"
    assert rec["build_min"] == 405, "a: latest 410, b: latest (by time) 405"
    assert rec["last_seen"] == "2026-11-17T11:30:00Z"
    assert rec["first_seen"] == "2026-11-17T09:00:00Z"


def test_reports_without_a_build_leave_it_null() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "a", "1", err("2026-11-17T10:00:00Z"))
    (rec,) = open_signatures(state)
    assert (rec["build"], rec["build_min"], rec["version_name"]) == (None, None, None)


def test_an_old_state_gains_the_fields_on_load(tmp_path: Path) -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "a", "1", err("2026-11-17T10:00:00Z"))
    (rec,) = state["signatures"].values()
    for field in (
        "app",
        "signature",
        "kind",
        "message",
        "top_frame",
        "first_seen",
        "last_seen",
        "build",
        "build_min",
        "version_name",
        "detail",
        "builds",
        "waits",
    ):
        rec.pop(field, None)  # type: ignore[misc]
    path = tmp_path / "state.json"
    path.write_text(json.dumps(state))
    (loaded,) = load_state(path)["signatures"].values()
    assert loaded["app"] == "kartka"
    assert loaded["signature"] == loaded["id"]
    assert loaded["message"] == "FormatException: bad <n>"
    assert loaded["build"] is None
    assert loaded["first_seen"] == loaded["first"]
    assert loaded["detail"] == {"routes": ["/reader/:id"], "sources": []}


def test_saved_state_json_carries_the_fields(tmp_path: Path) -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "a", "1", err("2026-11-17T10:00:00Z", build=7, version="v7"))
    path = tmp_path / "state.json"
    save_state(path, state)
    (rec,) = json.loads(path.read_text())["signatures"].values()
    assert {
        "app",
        "signature",
        "kind",
        "message",
        "top_frame",
        "count",
        "first_seen",
        "last_seen",
        "build",
        "version_name",
        "detail",
    } <= rec.keys()
