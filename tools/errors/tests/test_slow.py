# Copyright (c) 2026 Krzysztof Rudnicki
"""``perf.slow`` waits: one signature per route + operation, with durations."""

from pathlib import Path
from typing import cast

from kartka_errors.render import render
from kartka_errors.signature import signature
from kartka_errors.state import Entry, load_state, merge, open_signatures


def slow(
    at: str,
    ms: int,
    wait: str,
    *,
    op: str = "reader.open",
    route: str = "/reader/:id",
    **extra: object,
) -> Entry:
    base: dict[str, object] = {
        "at": at,
        "kind": "perf.slow",
        "error": f"{op} waited {ms} ms",
        "route": route,
        "operation": op,
        "durationMs": ms,
        "waitId": wait,
    }
    return cast("Entry", {**base, **extra})


def test_signature_ignores_duration_and_wait_id() -> None:
    a = signature(slow("2026-11-17T10:00:00Z", 1200, "w1"))
    b = signature(slow("2026-11-17T11:00:00Z", 98765, "w2"))
    assert a.id == b.id
    assert a.type == "perf.slow"
    assert a.where == "route /reader/:id"
    assert "1200" not in a.message


def test_signature_differs_by_route_and_operation() -> None:
    base = signature(slow("2026-11-17T10:00:00Z", 1200, "w1"))
    other_op = signature(slow("2026-11-17T10:00:00Z", 1200, "w1", op="reader.page"))
    other_route = signature(slow("2026-11-17T10:00:00Z", 1200, "w1", route="/library"))
    assert len({base.id, other_op.id, other_route.id}) == 3


def test_durations_merge_into_one_record_with_detail() -> None:
    state = load_state(Path("/nonexistent"))
    for i, ms in enumerate([1200, 3000, 2000, 9000]):
        assert merge(
            state, "dev-a", f"id{i}", slow(f"2026-11-17T10:0{i}:00Z", ms, f"w{i}")
        )
    (rec,) = open_signatures(state)
    assert rec["count"] == 4
    assert rec["detail"] == {
        "route": "/reader/:id",
        "operation": "reader.open",
        "count": 4,
        "max_ms": 9000,
        "p50_ms": 2500,
        "last_ms": 9000,
    }
    assert rec["kind"] == "perf.slow"
    assert rec["top_frame"] is None
    assert rec["message"] == "slow wait: reader.open"


def test_last_ms_follows_the_newest_report() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "d", "1", slow("2026-11-17T12:00:00Z", 1500, "w1"))
    merge(state, "d", "2", slow("2026-11-17T10:00:00Z", 8000, "w2"))
    (rec,) = open_signatures(state)
    assert rec["detail"]["last_ms"] == 1500
    assert rec["detail"]["max_ms"] == 8000


def test_a_wait_reported_twice_counts_once_with_its_final_duration() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "d", "1", slow("2026-11-17T10:00:05Z", 5000, "w1", still=True))
    merge(state, "d", "2", slow("2026-11-17T10:00:07Z", 7000, "w1"))
    merge(state, "d", "3", slow("2026-11-17T10:00:06Z", 6000, "w1", still=True))
    (rec,) = open_signatures(state)
    assert rec["count"] == 1
    assert rec["detail"]["count"] == 1
    assert rec["detail"]["max_ms"] == 7000
    assert rec["detail"]["last_ms"] == 7000


def test_same_wait_id_on_two_devices_is_two_waits() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "a", "1", slow("2026-11-17T10:00:00Z", 1200, "w1"))
    merge(state, "b", "1", slow("2026-11-17T10:00:00Z", 1300, "w1"))
    (rec,) = open_signatures(state)
    assert rec["count"] == 2


def test_wait_history_is_bounded() -> None:
    state = load_state(Path("/nonexistent"))
    for i in range(250):
        merge(state, "d", str(i), slow("2026-11-17T10:00:00Z", 1000 + i, f"w{i}"))
    (rec,) = open_signatures(state)
    assert rec["count"] == 250
    assert len(rec["waits"]) == 200
    assert rec["detail"]["max_ms"] == 1249


def test_a_slow_entry_without_its_fields_still_merges() -> None:
    state = load_state(Path("/nonexistent"))
    bare = cast(
        "Entry",
        {"at": "2026-11-17T10:00:00Z", "kind": "perf.slow", "error": "x waited 1 ms"},
    )
    assert merge(state, "d", "1", bare)
    (rec,) = open_signatures(state)
    assert rec["detail"]["operation"] == "?"
    assert rec["detail"]["max_ms"] == 0


def test_render_names_the_target() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "d", "1", slow("2026-11-17T10:00:00Z", 2400, "w1"))
    text = render(state, "2026-11-17T12:00:00Z")
    assert text is not None
    assert "under 1 s" in text
    assert "operation: `reader.open`" in text
    assert "max 2400 ms" in text
