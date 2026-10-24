# Copyright (c) 2026 Krzysztof Rudnicki
"""Turn a source's run state + uptime history into contract §5 metric blocks."""

from __future__ import annotations

import datetime as dt
import math
from statistics import median
from typing import TYPE_CHECKING, cast

from source_eval import imagequality, uptime
from source_eval.challenge import FLAG_BROWSER_ENGINE, WEBVIEW

if TYPE_CHECKING:
    from source_eval.models import Candidate
    from source_eval.polite import Observation
    from source_eval.state import Manifest, SourceState


def percentile(values: list[float], pct: float) -> float | None:
    """Nearest-rank percentile; ``None`` for no data."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(pct / 100 * len(ordered)) - 1)]


def _iso(ts: float) -> str:
    return dt.datetime.fromtimestamp(ts, dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _samples(
    state: SourceState, probes: list[Observation]
) -> list[tuple[float, bool, float, str | None, int | None]]:
    out = [(p.at, p.ok, p.ms, p.kind, p.status) for p in probes]
    for row in state.observations:
        at, ok, ms, kind, status = row
        out.append(
            (
                float(cast("float", at)),
                bool(ok),
                float(cast("float", ms)),
                cast("str | None", kind),
                cast("int | None", status),
            )
        )
    return out


def measured(cand: Candidate, state: SourceState) -> bool:
    """False when no backend could read the source at all (plugin stub...)."""
    return cand.origin != "plugin" and state.aborted != "unavailable"


def metrics(
    cand: Candidate,
    state: SourceState,
    manifest: Manifest,
    probes: list[Observation],
    now: float,
) -> dict[str, object]:
    """Every metric block of the record (no score/rank/verdict yet)."""
    samples = _samples(state, probes)
    responded = [s[2] for s in samples if s[4] is not None]
    challenged = [s[3] for s in samples if s[3]]
    p50, p95 = percentile(responded, 50), percentile(responded, 95)
    is_measured = measured(cand, state)
    found = len(state.found())
    ratios = [
        float(cast("float", c["ratio"]))
        for c in state.chapters.values()
        if c.get("ratio") is not None
    ]
    pages = [
        p
        for img in state.images.values()
        for p in cast("list[dict[str, object]]", img["pages"])
    ]
    last = max((s[0] for s in samples), default=now)
    return {
        "id": cand.id,
        "name": cand.name,
        "lang": cand.lang,
        "origin": cand.origin,
        "probedAt": _iso(last),
        "uptime": uptime.summarize(probes, now),
        "latencyMs": {
            "p50": round(p50) if p50 is not None else None,
            "p95": round(p95) if p95 is not None else None,
        },
        "blocking": {
            "challengeRate": round(len(challenged) / len(samples), 3)
            if samples
            else 0.0,
            "kinds": sorted(set(challenged)),
        },
        "flags": [FLAG_BROWSER_ENGINE] if WEBVIEW in challenged else [],
        "coverage": {
            "referenceSize": len(manifest.sample),
            "found": found if is_measured else None,
            "ratio": round(found / len(manifest.sample), 3)
            if is_measured and manifest.sample
            else None,
        },
        "chapterCompleteness": {
            "sampled": len(ratios),
            "medianRatio": round(median(ratios), 3) if ratios else None,
        },
        "imageQuality": imagequality.summarize(pages),
        "availability": cand.availability.to_json(),
    }
