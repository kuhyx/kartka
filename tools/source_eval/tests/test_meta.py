# Copyright (c) 2026 Krzysztof Rudnicki
"""The run meta block: published to its own RTDB node and kept in latest.json."""

from __future__ import annotations

from source_eval import report
from source_eval.profile import DEFAULT
from source_eval.state import sha1

SKIPPED: list[dict[str, object]] = [
    {"index": "keiyoushi", "reason": "language", "count": 2, "names": ["A", "B"]}
]


def test_build_meta_counts_verdicts() -> None:
    ranked: list[dict[str, object]] = [
        {"id": "a", "verdict": "keep"},
        {"id": "b", "verdict": "cut"},
        {"id": "c", "verdict": "cut"},
        {"id": "d", "verdict": "pending"},
    ]
    meta = report.build_meta("2026-W44", "2026-10-25T00:00:00Z", 9, ranked, SKIPPED)
    assert meta == {
        "runId": "2026-W44",
        "generatedAt": "2026-10-25T00:00:00Z",
        "candidates": 9,
        "tested": 4,
        "verdicts": {"keep": 1, "cut": 2, "pending": 1},
        "skipped": SKIPPED,
        "profile": {"name": "default", **DEFAULT.to_json()},
    }
    empty = report.build_meta("r", "t", 0, [], [])
    assert empty["verdicts"] == {"keep": 0, "cut": 0, "pending": 0}


def test_publish_writes_records_then_meta() -> None:
    calls: list[tuple[str, dict[str, object]]] = []

    class Writer:
        def patch(self, path: str, data: dict[str, object]) -> None:
            calls.append((path, data))

    records: list[dict[str, object]] = [
        {"id": "x", "verdict": "keep"},
        {"id": "y", "verdict": "cut"},
    ]
    meta = report.build_meta("r", "t", 2, records, SKIPPED)
    rep: dict[str, object] = {"sources": records, "meta": meta}
    assert report.publish(rep, Writer()) == 2
    assert report.META_PATH == "kartka/source_health_meta"
    assert calls == [
        (report.RTDB_PATH, {sha1("x"): records[0], sha1("y"): records[1]}),
        (report.META_PATH, meta),
    ]
