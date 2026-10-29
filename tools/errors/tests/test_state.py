# Copyright (c) 2026 Krzysztof Rudnicki
from pathlib import Path
from typing import cast

from kartka_errors.signature import signature
from kartka_errors.state import (
    Entry,
    load_state,
    merge,
    open_signatures,
    prune,
    resolve,
    save_state,
)


def entry(at: str, error: str = "FormatException: bad", **extra: str) -> Entry:
    base = {
        "at": at,
        "kind": "ui.snackbar",
        "error": error,
        "stack": ["#0 f (package:kartka/p.dart:1:1)"],
    }
    return cast("Entry", {**base, **extra})


def test_merge_counts_once_per_entry_and_tracks_where() -> None:
    state = load_state(Path("/nonexistent/state.json"))
    assert merge(state, "dev-a", "id1", entry("2026-10-29T10:00:00.000Z", route="/a"))
    assert not merge(state, "dev-a", "id1", entry("2026-10-29T10:00:00.000Z"))
    assert merge(
        state,
        "dev-b",
        "id2",
        entry("2026-10-28T09:00:00.000Z", route="/b", sourceId="suwayomi"),
    )
    (sig,) = open_signatures(state)
    assert sig["count"] == 2
    assert sig["first"] == "2026-10-28T09:00:00.000Z"
    assert sig["last"] == "2026-10-29T10:00:00.000Z"
    assert sig["devices"] == ["dev-a", "dev-b"]
    assert sig["routes"] == ["/a", "/b"]
    assert sig["sources"] == ["suwayomi"]
    assert sig["kinds"] == ["ui.snackbar"]
    assert sig["sample"]["error"] == "FormatException: bad"


def test_resolved_stays_closed_until_it_happens_again() -> None:
    state = load_state(Path("/nonexistent"))
    e = entry("2026-10-29T10:00:00.000Z")
    merge(state, "d", "1", e)
    sig_id = signature(e).id
    assert resolve(state, sig_id[:6], "2026-10-29T11:00:00Z") == [sig_id]
    assert open_signatures(state) == []
    merge(state, "d", "2", entry("2026-10-29T10:30:00.000Z"))
    assert open_signatures(state) == [], "older than the fix"
    merge(state, "d", "3", entry("2026-10-29T12:00:00.000Z"))
    (sig,) = open_signatures(state)
    assert sig["reopened"] is True
    assert resolve(state, "zzz", "x") == []


def test_round_trips_through_disk_and_prunes_old_ids(tmp_path: Path) -> None:
    path = tmp_path / "sub" / "state.json"
    state = load_state(path)
    merge(state, "d", "old", entry("2026-01-01T00:00:00.000Z"))
    merge(state, "d", "new", entry("2026-10-29T00:00:00.000Z"))
    prune(state, "2026-10-29T12:00:00Z", days=60)
    save_state(path, state)
    back = load_state(path)
    assert set(back["seen"]) == {"d/new"}
    assert open_signatures(back)[0]["count"] == 2
    path.write_text("not json")
    assert load_state(path)["signatures"] == {}


def test_open_signatures_are_newest_first() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "d", "1", entry("2026-10-28T00:00:00.000Z", error="A: old"))
    merge(state, "d", "2", entry("2026-10-29T00:00:00.000Z", error="B: new"))
    assert [s["sample"]["error"] for s in open_signatures(state)] == [
        "B: new",
        "A: old",
    ]


def test_a_state_of_another_version_starts_empty(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    path.write_text('{"version": 9, "seen": {"x": "y"}}')
    assert load_state(path)["seen"] == {}
