# Copyright (c) 2026 Krzysztof Rudnicki
"""Turn a source's run state + uptime history into contract §5 metric blocks."""

from __future__ import annotations

import datetime as dt
import math
from statistics import median
from typing import TYPE_CHECKING, cast

from source_eval import imagequality, uptime
from source_eval.candidates.catalog import MANGAYOMI_INDEX
from source_eval.challenge import FLAG_BROWSER_ENGINE, WEBVIEW
from source_eval.evaluate import DEAD_AFTER
from source_eval.score import COMPLETE_CHAPTERS

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


def pages_load(state: SourceState) -> dict[str, object]:
    """Share of sampled chapters whose page images all downloaded.

    Each ``state.images`` entry is one attempted chapter; it counts as loaded
    only with no error and at least one measured page.
    """
    tried = list(state.images.values())
    ok = sum(1 for img in tried if "error" not in img and img.get("pages"))
    return {
        "ratio": round(ok / len(tried), 3) if tried else None,
        "sampled": len(tried),
    }


def complete_titles(state: SourceState) -> int:
    """Found titles whose chapter list is complete enough to count.

    At least ``COMPLETE_CHAPTERS`` of the reference chapter count (the stored
    ratio is capped at 1), or at least one chapter when the reference has no
    count. A failed or missing chapter list never counts.
    """
    count = 0
    for key in state.found():
        ch = state.chapters.get(key)
        if ch is None or "error" in ch:
            continue
        ratio = ch.get("ratio")
        if ratio is None:
            count += int(cast("int", ch.get("count") or 0) >= 1)
        else:
            count += int(float(cast("float", ratio)) >= COMPLETE_CHAPTERS)
    return count


def unreachable(state: SourceState) -> bool:
    """Aborted as unreachable, unless only for a browser-engine need.

    The first searches all failing with ``webview`` is a source that needs a
    browser engine: flagged, never cut.
    """
    if state.aborted != "unreachable":
        return False
    head = list(state.titles.values())[:DEAD_AFTER]
    return any(r.get("kind") != WEBVIEW for r in head)


def install_info(cand: Candidate) -> dict[str, object]:
    """What installs the source: Tachiyomi ``pkg``, or a Kartka plugin.

    ``plugin`` is ``{repo, id}`` for a Mangayomi JS source (the index the
    app's plugin manager reads, and the Kartka plugin id); ``None`` for a
    legacy source no repo serves.
    """
    plugin_id = cand.id.removeprefix("plugin:")
    plugin = (
        {"repo": MANGAYOMI_INDEX, "id": plugin_id}
        if plugin_id.startswith("mangayomi-")
        else None
    )
    return {"pkg": cand.pkg or None, "plugin": plugin}


def lang_scope(cand: Candidate) -> str:
    """``en+ja`` when only English/Japanese content was measured.

    A multi-language (``all``) source is measured as the backend serves it:
    no backend restricts one to en/ja yet.
    """
    return "unrestricted" if cand.lang == "all" else "en+ja"


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
    hard = [kind for kind in challenged if kind != WEBVIEW]
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
            "hardRate": round(len(hard) / len(samples), 3) if samples else 0.0,
        },
        "unreachable": unreachable(state),
        "flags": [FLAG_BROWSER_ENGINE] if WEBVIEW in challenged else [],
        "coverage": {
            "referenceSize": len(manifest.sample),
            "found": found if is_measured else None,
            "ratio": round(found / len(manifest.sample), 3)
            if is_measured and manifest.sample
            else None,
            **_complete(state, manifest, is_measured=is_measured),
        },
        "chapterCompleteness": {
            "sampled": len(ratios),
            "medianRatio": round(median(ratios), 3) if ratios else None,
        },
        "imageQuality": imagequality.summarize(pages),
        "pagesLoad": pages_load(state),
        "langScope": lang_scope(cand),
        "availability": cand.availability.to_json(),
        **install_info(cand),
    }


def _complete(
    state: SourceState, manifest: Manifest, *, is_measured: bool
) -> dict[str, object]:
    """Merged coverage: ``complete`` titles and their share of the sample.

    Both ``None`` unless the run fetched every found title's chapter list
    (``Manifest.all_chapters``) and the source was measured.
    """
    if not (manifest.all_chapters and is_measured and manifest.sample):
        return {"complete": None, "completeRatio": None}
    complete = complete_titles(state)
    return {
        "complete": complete,
        "completeRatio": round(complete / len(manifest.sample), 3),
    }
