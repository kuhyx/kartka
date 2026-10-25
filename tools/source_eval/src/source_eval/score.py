# Copyright (c) 2026 Krzysztof Rudnicki
"""Score, rank and verdicts (contract §5) under a scoring profile.

Under the DEFAULT profile no cut switch is on, so the verdict is the score
alone and cut reasons only explain a low score; a custom profile can turn
reasons into cuts.
"""

from __future__ import annotations

from typing import cast

from source_eval.challenge import WEBVIEW
from source_eval.profile import DEFAULT, Profile

UPTIME_MIN = 0.95
COVERAGE_MIN = 0.60
SUBSET_MIN = 0.90
#: The DEFAULT profile's keep bar (kept for readers of the old constant).
KEEP_SCORE = DEFAULT.keep_score
#: Image width that earns the full image-quality score, and the p95 latency
#: at which the speed score reaches 0.
WIDTH_FULL, P95_ZERO = 1400.0, 5000.0
_ORIGIN_ORDER = {"native": 0, "suwayomi": 1, "plugin": 2}

Record = dict[str, object]


def _get(record: Record, block: str, key: str) -> float | None:
    value = cast("dict[str, object]", record[block]).get(key)
    return float(cast("float", value)) if value is not None else None


def _pages_ratio(record: Record) -> float | None:
    block = cast("dict[str, object] | None", record.get("pagesLoad"))
    value = block.get("ratio") if block else None
    return float(cast("float", value)) if value is not None else None


def score(record: Record, profile: Profile = DEFAULT) -> float:
    """Normalised weighted score in [0, 1]; an unmeasured metric contributes 0.

    With the profile's pages-load multiplier on, the sum is multiplied by
    ``pagesLoad.ratio`` when that is known, so a source whose page images
    never download scores 0.
    """
    coverage = _get(record, "coverage", "ratio") or 0.0
    complete = _get(record, "chapterCompleteness", "medianRatio") or 0.0
    up = _get(record, "uptime", "ratio") or 0.0
    width = _get(record, "imageQuality", "medianWidthPx")
    p95 = _get(record, "latencyMs", "p95")
    quality = min(1.0, width / WIDTH_FULL) if width is not None else 0.0
    speed = max(0.0, 1.0 - p95 / P95_ZERO) if p95 is not None else 0.0
    weights = profile.weights.normalised()
    parts = (coverage, complete, up, quality, speed)
    total = sum(w * part for w, part in zip(weights, parts, strict=True))
    pages = _pages_ratio(record) if profile.pages_load_multiplier else None
    return round(total * pages if pages is not None else total, 3)


def _blocked(record: Record) -> bool:
    """Any challenge other than ``webview`` (that one is flagged, not cut)."""
    block = cast("dict[str, object]", record["blocking"])
    if (_get(record, "blocking", "challengeRate") or 0.0) <= 0:
        return False
    kinds = cast("list[str]", block.get("kinds") or [])
    return not kinds or any(kind != WEBVIEW for kind in kinds)


def cut_reasons(record: Record) -> list[str]:
    """Explanations of a low score, except ``subset`` (needs the ranking).

    Explanatory only: they never decide the verdict. Page loading has no
    reason of its own; it lowers the score (``pagesLoad.ratio`` multiplies it).
    """
    reasons = []
    up = cast("dict[str, object]", record["uptime"])
    ratio = _get(record, "uptime", "ratio")
    if up["status"] == "final" and ratio is not None and ratio < UPTIME_MIN:
        reasons.append("uptime<0.95")
    if _blocked(record):
        reasons.append("blocking")
    coverage = _get(record, "coverage", "ratio")
    if coverage is not None and coverage < COVERAGE_MIN:
        reasons.append("coverage<0.60")
    return reasons


def applicable_cuts(record: Record) -> set[str]:
    """Wire names of the cut reasons that apply to a ranked ``record``.

    From its published ``cutReasons`` (which include ``subset``), the
    ``needs-browser-engine`` flag and a ``pagesLoad.ratio`` of exactly 0.
    """
    codes = cast("list[str]", record.get("cutReasons") or [])
    applies = {
        name
        for name in ("blocking", "subset", "coverage", "uptime")
        if any(code.startswith(name) for code in codes)
    }
    if "needs-browser-engine" in cast("list[str]", record.get("flags") or []):
        applies.add("needsBrowserEngine")
    if _pages_ratio(record) == 0:
        applies.add("pagesNeverLoad")
    return applies


def verdict(record: Record, profile: Profile = DEFAULT) -> str:
    """An enabled cut switch whose reason applies cuts; else the score decides.

    Else ``keep`` at ``keepScore`` or more, ``pending`` while unmeasured
    (``coverage.ratio`` is null), otherwise ``cut``.
    """
    if applicable_cuts(record) & profile.cuts.enabled():
        return "cut"
    if cast("float", record["score"]) >= profile.keep_score:
        return "keep"
    return "pending" if _get(record, "coverage", "ratio") is None else "cut"


def _wider_or_equal(better: Record, worse: Record) -> bool:
    w_better = _get(better, "imageQuality", "medianWidthPx")
    w_worse = _get(worse, "imageQuality", "medianWidthPx")
    if w_worse is None:
        return True
    return w_better is not None and w_better >= w_worse


def rank(
    records: list[Record],
    found: dict[str, set[str]],
    profile: Profile = DEFAULT,
) -> list[Record]:
    """Score, rank (1 = best) and judge every record; returns them in rank order.

    ``found`` maps source id to the reference keys it found. A source whose
    found titles are >= 90 % found by a higher-ranked, not-cut source with
    at least its image width gets ``subsetOf`` and a ``subset`` cut reason
    (explanatory unless the profile's ``subset`` switch is on). Every record
    carries ``score`` under ``profile`` and ``defaultScore`` under DEFAULT.
    """
    for record in records:
        record["score"] = score(record, profile)
        record["defaultScore"] = score(record, DEFAULT)
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
        record["verdict"] = verdict(record, profile)
    return ordered
