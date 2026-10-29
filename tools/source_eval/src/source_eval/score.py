# Copyright (c) 2026 Krzysztof Rudnicki
"""Score, rank and verdicts (contract §5) under a scoring profile.

Hard filter (unreachable, or >= 50 % non-webview challenges) first, then the
profile's cut switches, then the score; a subset gets a graded penalty. The
rank order is :mod:`source_eval.tier` (browser engine / challenge rank low).
"""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal
from typing import cast

from source_eval.challenge import WEBVIEW
from source_eval.profile import DEFAULT, Profile
from source_eval.tier import ordered

UPTIME_MIN, COVERAGE_MIN = 0.95, 0.60
#: Overlap with a better source from which the subset penalty applies,
#: multiplying the score by ``1 - SUBSET_PENALTY * overlap``.
SUBSET_MIN, SUBSET_PENALTY = 0.50, 0.5
#: A non-webview challenge rate at or above this cuts (hard filter).
HARD_CHALLENGE_RATE = 0.5
#: Share of the reference chapter count a found title needs to count.
COMPLETE_CHAPTERS = 0.8
#: Old runs: this share of coverage + the rest of completeness (.30/.20).
LEGACY_COVERAGE_SHARE = 0.6
UNREACHABLE, HARD_BLOCKING = "unreachable", "blocking>=0.50"  # hard filter
HARD_CODES = frozenset({UNREACHABLE, HARD_BLOCKING})
#: The DEFAULT profile's keep bar (kept for readers of the old constant).
KEEP_SCORE = DEFAULT.keep_score
#: Width earning full image quality; p95 latency at which speed reaches 0.
WIDTH_FULL, P95_ZERO = 1067.0, 5000.0
_THOUSANDTH = Decimal("0.001")

Record = dict[str, object]


def round3(value: float) -> float:
    """``value`` to 3 places from its exact binary value, halves up.

    The app rounds the same way (``toStringAsFixed(3)``), so both sides agree
    on every score, including near-ties that ``round()`` would break evenly.
    """
    return float(Decimal(value).quantize(_THOUSANDTH, rounding=ROUND_HALF_UP))


def _get(record: Record, block: str, key: str) -> float | None:
    value = cast("dict[str, object]", record.get(block) or {}).get(key)
    return float(cast("float", value)) if value is not None else None


def _pages_ratio(record: Record) -> float | None:
    block = cast("dict[str, object] | None", record.get("pagesLoad"))
    value = block.get("ratio") if block else None
    return float(cast("float", value)) if value is not None else None


def coverage_part(record: Record) -> float:
    """The merged coverage part: ``coverage.completeRatio``.

    A run before the merged metric has none; then it is the old coverage and
    chapter completeness in their old proportion (unmeasured counts as 0).
    """
    complete = _get(record, "coverage", "completeRatio")
    if complete is not None:
        return complete
    coverage = _get(record, "coverage", "ratio") or 0.0
    chapters = _get(record, "chapterCompleteness", "medianRatio") or 0.0
    return LEGACY_COVERAGE_SHARE * coverage + (1 - LEGACY_COVERAGE_SHARE) * chapters


def subset_factor(record: Record) -> float:
    """``1 - SUBSET_PENALTY * overlap`` from the published ``subsetOf``, else 1."""
    subset = cast("dict[str, object] | None", record.get("subsetOf"))
    overlap = subset.get("overlap") if subset else None
    if overlap is None:
        return 1.0
    return 1.0 - SUBSET_PENALTY * float(cast("float", overlap))


def _raw(record: Record, profile: Profile) -> float:
    up = _get(record, "uptime", "ratio") or 0.0
    width = _get(record, "imageQuality", "medianWidthPx")
    p95 = _get(record, "latencyMs", "p95")
    quality = min(1.0, width / WIDTH_FULL) if width is not None else 0.0
    speed = max(0.0, 1.0 - p95 / P95_ZERO) if p95 is not None else 0.0
    parts = (coverage_part(record), up, quality, speed)
    total = 0.0
    for weight, part in zip(profile.weights.normalised(), parts, strict=True):
        total += weight * part
    pages = _pages_ratio(record) if profile.pages_load_multiplier else None
    return total * pages if pages is not None else total


def score(record: Record, profile: Profile = DEFAULT) -> float:
    """Normalised weighted score in [0, 1]; an unmeasured metric contributes 0.

    With the profile's pages-load multiplier on, the sum is multiplied by
    ``pagesLoad.ratio`` when that is known; a published ``subsetOf`` then
    multiplies it by :func:`subset_factor`. Rounded by :func:`round3`.
    """
    return round3(_raw(record, profile) * subset_factor(record))


def _blocked(record: Record) -> bool:
    """Any challenge other than ``webview`` (that one is flagged, not cut)."""
    if (_get(record, "blocking", "challengeRate") or 0.0) <= 0:
        return False
    kinds = cast("list[str]", _block(record, "blocking").get("kinds") or [])
    return not kinds or any(kind != WEBVIEW for kind in kinds)


def _block(record: Record, name: str) -> dict[str, object]:
    return cast("dict[str, object]", record.get(name) or {})


def cut_reasons(record: Record) -> list[str]:
    """Hard-filter codes and explanations of a low score, except ``subset``.

    ``unreachable`` and ``blocking>=0.50`` (non-webview challenge rate at
    least ``HARD_CHALLENGE_RATE``, or a challenged re-probe) cut; the others
    only explain. Page loading has no reason; it lowers the score.
    """
    reasons = [UNREACHABLE] if record.get("unreachable") is True else []
    ratio = _get(record, "uptime", "ratio")
    final = _block(record, "uptime").get("status") == "final"
    if final and ratio is not None and ratio < UPTIME_MIN:
        reasons.append("uptime<0.95")
    probe = _block(record, "reprobe")  # a failed re-probe keeps its hard cut
    hard_rate = _get(record, "blocking", "hardRate") or 0.0
    if (probe.get("passed") is False and probe.get("kind")) or (
        hard_rate >= HARD_CHALLENGE_RATE
    ):
        reasons.append(HARD_BLOCKING)
    elif _blocked(record):
        reasons.append("blocking")
    coverage = _get(record, "coverage", "ratio")
    if coverage is not None and coverage < COVERAGE_MIN:
        reasons.append("coverage<0.60")
    return reasons


def applicable_cuts(record: Record) -> set[str]:
    """Wire names of the cut switches that apply to a ranked ``record``.

    From its ``cutReasons``, the ``needs-browser-engine`` flag and a
    ``pagesLoad.ratio`` of exactly 0.
    """
    codes = cast("list[str]", record.get("cutReasons") or [])
    applies = {
        name
        for name in ("blocking", "coverage", "uptime")
        if any(code.startswith(name) for code in codes)
    }
    if "needs-browser-engine" in cast("list[str]", record.get("flags") or []):
        applies.add("needsBrowserEngine")
    if _pages_ratio(record) == 0:
        applies.add("pagesNeverLoad")
    return applies


def verdict(record: Record, profile: Profile = DEFAULT) -> str:
    """Hard filter, then the enabled cut switches, then the score.

    ``cut`` for a hard-filter code; else an enabled switch whose reason
    applies cuts; else ``keep`` at ``keepScore`` or more, ``pending`` while
    unmeasured (``coverage.ratio`` is null), otherwise ``cut``.
    """
    codes = cast("list[str]", record.get("cutReasons") or [])
    if HARD_CODES.intersection(codes):
        return "cut"
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


def _subset_of(
    ordered: list[Record], position: int, found: dict[str, set[str]]
) -> dict[str, object] | None:
    """The best qualifying overlap of ``ordered[position]`` with a better one."""
    record = ordered[position]
    mine = found.get(str(record["id"]), set())
    best: tuple[float, str] | None = None
    for better in ordered[:position]:
        if (
            better["verdict"] == "cut"
            or not mine
            or not _wider_or_equal(better, record)
        ):
            continue
        overlap = len(mine & found.get(str(better["id"]), set())) / len(mine)
        if overlap >= SUBSET_MIN and (best is None or overlap > best[0]):
            best = (overlap, str(better["id"]))
    return None if best is None else {"sourceId": best[1], "overlap": round3(best[0])}


def rank(
    records: list[Record],
    found: dict[str, set[str]],
    profile: Profile = DEFAULT,
) -> list[Record]:
    """Score, rank (1 = best) and judge every record; returns them in rank order.

    One pass, no feedback: a base ranking without subsets decides which
    sources are better and not cut; a source whose found titles (``found``
    maps id to reference keys) are >= 50 % found by such a better source with
    at least its image width gets ``subsetOf`` (the published, rounded
    overlap), a ``subset`` reason and the penalty; then the final ranking and
    verdicts. ``score`` is under ``profile``, ``defaultScore`` under DEFAULT,
    both with the penalty.
    """
    for record in records:
        record["subsetOf"] = None
        record["cutReasons"] = cut_reasons(record)
        record["score"] = score(record, profile)
        record["verdict"] = verdict(record, profile)
    base = ordered(records)
    subsets = [_subset_of(base, i, found) for i in range(len(base))]
    for record, subset in zip(base, subsets, strict=True):
        if subset is not None:
            record["subsetOf"] = subset
            record["cutReasons"] = [*cast("list[str]", record["cutReasons"]), "subset"]
        record["score"] = score(record, profile)
        record["defaultScore"] = score(record, DEFAULT)
    final = ordered(records)
    for position, record in enumerate(final, start=1):
        record["rank"] = position
        record["verdict"] = verdict(record, profile)
    return final
