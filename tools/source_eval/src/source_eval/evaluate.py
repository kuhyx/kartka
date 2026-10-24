# Copyright (c) 2026 Krzysztof Rudnicki
"""Measure one source in resumable steps: search -> chapters -> images."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

from source_eval.budget import stratified
from source_eval.challenge import WEBVIEW
from source_eval.imagequality import measure
from source_eval.match import best_hit
from source_eval.models import Chapter, Hit, SourceError

if TYPE_CHECKING:
    from source_eval.backends.base import Backend
    from source_eval.budget import Deadline
    from source_eval.models import Candidate, RefTitle
    from source_eval.state import Manifest, SourceState

#: Stop spending searches on a source after this many challenged requests...
BLOCKED_AFTER = 3
#: ...or when this many first searches all failed outright.
DEAD_AFTER = 5


def _queries(ref: RefTitle) -> list[str]:
    return list(dict.fromkeys(ref.titles[:2]))


def _search(backend: Backend, cand: Candidate, ref: RefTitle) -> dict[str, object]:
    try:
        for query in _queries(ref):
            hit = best_hit(backend.search(cand, query), ref)
            if hit is not None:
                return {"status": "found", "hit": {"title": hit.title, "ref": hit.ref}}
    except SourceError as exc:
        return {"status": "error", "kind": exc.kind, "error": str(exc)[:300]}
    return {"status": "missing"}


def _abort_reason(state: SourceState) -> str | None:
    results = list(state.titles.values())
    # A browser-engine need is flagged, not blocking: keep measuring.
    hard = [r for r in results if r.get("kind") not in (None, WEBVIEW)]
    if len(hard) >= BLOCKED_AFTER:
        return "blocking"
    head = results[:DEAD_AFTER]
    if len(head) == DEAD_AFTER and all(r["status"] == "error" for r in head):
        return "unreachable"
    return None


def _count(chapters: list[Chapter]) -> int:
    numbered = {c.number for c in chapters if c.number is not None}
    return len(numbered) if numbered else len(chapters)


def _chapter_step(
    backend: Backend, cand: Candidate, ref: RefTitle, hit: Hit
) -> dict[str, object]:
    try:
        chapters = backend.chapters(cand, hit)
    except SourceError as exc:
        return {"error": str(exc)[:300], "kind": exc.kind}
    count = _count(chapters)
    ratio = min(1.0, count / ref.chapters) if ref.chapters else None
    pick = chapters[len(chapters) // 2].ref if chapters else None
    return {"count": count, "ratio": ratio, "pick": pick}


def _image_step(
    backend: Backend, cand: Candidate, chapter_ref: str, pages: int
) -> dict[str, object]:
    try:
        images = backend.pages(cand, Chapter(chapter_ref, None))
        # Skip the first page (often a cover or credits) when there is a choice.
        body = images[1:] if len(images) > pages else images
        picked = [
            body[int(i)] for i in stratified([str(i) for i in range(len(body))], pages)
        ]
        samples = []
        for page in picked:
            s = measure(backend.image(cand, page))
            samples.append(
                {
                    "width": s.width,
                    "height": s.height,
                    "fmt": s.fmt,
                    "jpegQuality": s.jpeg_quality,
                }
            )
    except SourceError as exc:
        return {"error": str(exc)[:300], "kind": exc.kind, "pages": []}
    return {"pages": samples}


@dataclass(frozen=True, slots=True)
class Plan:
    """What every source in a run is measured against."""

    refs: dict[str, RefTitle]
    manifest: Manifest


def _prepare(cand: Candidate, backend: Backend, state: SourceState) -> None:
    if state.prepared:
        return
    try:
        backend.prepare(cand)
    except SourceError as exc:
        state.aborted, state.error, state.done = "unavailable", str(exc)[:300], True
    else:
        state.prepared = True
    state.save()


def _searches(job: _Job) -> bool:
    for key in job.plan.manifest.sample:
        if job.state.aborted:
            break
        if key in job.state.titles:
            continue
        if job.deadline.expired():
            return False
        job.state.titles[key] = _search(job.backend, job.cand, job.plan.refs[key])
        job.state.aborted = _abort_reason(job.state)
        job.state.save()
    return True


def _chapter_lists(job: _Job) -> bool:
    state = job.state
    for key in list(state.found())[: job.plan.manifest.completeness]:
        if key in state.chapters:
            continue
        if job.deadline.expired():
            return False
        hit = cast("dict[str, str]", state.titles[key]["hit"])
        found = Hit(hit["title"], hit["ref"])
        state.chapters[key] = _chapter_step(
            job.backend, job.cand, job.plan.refs[key], found
        )
        state.save()
    return True


def _image_samples(job: _Job) -> bool:
    state, manifest = job.state, job.plan.manifest
    picks = [(k, v["pick"]) for k, v in state.chapters.items() if v.get("pick")]
    for key, pick in picks[: manifest.images]:
        if key in state.images:
            continue
        if job.deadline.expired():
            return False
        state.images[key] = _image_step(
            job.backend, job.cand, str(pick), manifest.pages
        )
        state.save()
    return True


@dataclass(frozen=True, slots=True)
class _Job:
    cand: Candidate
    backend: Backend
    state: SourceState
    plan: Plan
    deadline: Deadline


def evaluate(
    cand: Candidate,
    backend: Backend,
    state: SourceState,
    plan: Plan,
    deadline: Deadline,
) -> bool:
    """Advance ``cand``'s measurement; True when it is finished.

    Steps run in order and each checkpoints to disk, so an expired
    ``deadline`` just means the next call carries on.
    """
    _prepare(cand, backend, state)
    if state.done:
        return True
    job = _Job(cand, backend, state, plan, deadline)
    if not (_searches(job) and _chapter_lists(job) and _image_samples(job)):
        return False
    state.done = True
    state.save()
    return True
