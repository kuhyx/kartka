# Copyright (c) 2026 Krzysztof Rudnicki
"""Score, rank, subset detection and verdicts (contract §5 rules)."""

from __future__ import annotations

from typing import cast

UPTIME_MIN = 0.95
COVERAGE_MIN = 0.60
SUBSET_MIN = 0.90
_WIDTH_FULL, _P95_ZERO = 1400.0, 5000.0
_ORIGIN_ORDER = {"native": 0, "suwayomi": 1, "plugin": 2}

Record = dict[str, object]


def _get(record: Record, block: str, key: str) -> float | None:
    value = cast("dict[str, object]", record[block]).get(key)
    return float(cast("float", value)) if value is not None else None


def score(record: Record) -> float:
    """Weighted score in [0, 1]; an unmeasured metric contributes 0."""
    coverage = _get(record, "coverage", "ratio") or 0.0
    complete = _get(record, "chapterCompleteness", "medianRatio") or 0.0
    up = _get(record, "uptime", "ratio") or 0.0
    width = _get(record, "imageQuality", "medianWidthPx")
    p95 = _get(record, "latencyMs", "p95")
    quality = min(1.0, width / _WIDTH_FULL) if width is not None else 0.0
    speed = max(0.0, 1.0 - p95 / _P95_ZERO) if p95 is not None else 0.0
    total = (
        0.30 * coverage + 0.20 * complete + 0.20 * up + 0.15 * quality + 0.15 * speed
    )
    return round(total, 3)


def cut_reasons(record: Record) -> list[str]:
    """Contract cut rules, except ``subset`` (needs the ranking)."""
    reasons = []
    up = cast("dict[str, object]", record["uptime"])
    ratio = _get(record, "uptime", "ratio")
    if up["status"] == "final" and ratio is not None and ratio < UPTIME_MIN:
        reasons.append("uptime<0.95")
    if (_get(record, "blocking", "challengeRate") or 0.0) > 0:
        reasons.append("blocking")
    coverage = _get(record, "coverage", "ratio")
    if coverage is not None and coverage < COVERAGE_MIN:
        reasons.append("coverage<0.60")
    return reasons


def _verdict(record: Record, reasons: list[str]) -> str:
    if reasons:
        return "cut"
    accruing = cast("dict[str, object]", record["uptime"])["status"] != "final"
    unmeasured = _get(record, "coverage", "ratio") is None
    return "pending" if accruing or unmeasured else "keep"


def _wider_or_equal(better: Record, worse: Record) -> bool:
    w_better = _get(better, "imageQuality", "medianWidthPx")
    w_worse = _get(worse, "imageQuality", "medianWidthPx")
    if w_worse is None:
        return True
    return w_better is not None and w_better >= w_worse


def rank(records: list[Record], found: dict[str, set[str]]) -> list[Record]:
    """Score, rank (1 = best) and judge every record; returns them in rank order.

    ``found`` maps source id to the reference keys it found. A source whose
    found titles are >= 90 % found by a higher-ranked, not-cut source with
    at least its image width is a ``subset`` and is cut.
    """
    for record in records:
        record["score"] = score(record)
    ordered = sorted(
        records,
        key=lambda r: (
            -cast("float", r["score"]),
            _ORIGIN_ORDER.get(str(r["origin"]), 9),
            str(r["id"]),
        ),
    )
    for position, record in enumerate(ordered, start=1):
        record["rank"] = position
        reasons = cut_reasons(record)
        record["subsetOf"] = None
        mine = found.get(str(record["id"]), set())
        best: tuple[float, str] | None = None
        for better in ordered[: position - 1]:
            if (
                better["verdict"] == "cut"
                or not mine
                or not _wider_or_equal(better, record)
            ):
                continue
            overlap = len(mine & found.get(str(better["id"]), set())) / len(mine)
            if overlap >= SUBSET_MIN and (best is None or overlap > best[0]):
                best = (overlap, str(better["id"]))
        if best is not None:
            record["subsetOf"] = {"sourceId": best[1], "overlap": round(best[0], 3)}
            reasons.append("subset")
        record["cutReasons"] = reasons
        record["verdict"] = _verdict(record, reasons)
    return ordered
