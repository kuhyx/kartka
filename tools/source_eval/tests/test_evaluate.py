# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

from typing import cast
lazy from pathlib import Path

from source_eval.budget import Deadline
from source_eval.evaluate import Plan, evaluate
from source_eval.metrics import metrics, percentile
from source_eval.models import Candidate, Chapter, Hit, PageImage, RefTitle, SourceError
from source_eval.polite import Observation
from source_eval.state import Manifest, RunDir
from tests.fakes import FakeClock, fixture_bytes
lazy from source_eval.backends.base import Backend

CAND = Candidate("suwayomi:1", "Fake", "en", "suwayomi", "https://fake.test")
REFS = {
    "r1": RefTitle("r1", ("Alpha Story", "Arufa"), 10, "anilist"),
    "r2": RefTitle("r2", ("Beta",), None),
    "r3": RefTitle("r3", ("Gamma", "Ganma"), 4, "mangaupdates"),
    "r4": RefTitle("r4", ("Delta",), 2, "anilist"),
}
MANIFEST = Manifest(["r1", "r2", "r3", "r4"], completeness=3, images=2, pages=2)
PLAN = Plan(REFS, MANIFEST)


class FakeBackend:
    """Scripted backend: knows Alpha/Beta/Ganma, Delta has no chapters."""

    def __init__(
        self,
        *,
        fail_prepare: bool = False,
        kind: str | None = None,
        clock: FakeClock | None = None,
    ) -> None:
        self.fail_prepare = fail_prepare
        self.kind = kind
        self.clock = clock
        self.calls: list[str] = []

    def _tick(self, what: str) -> None:
        self.calls.append(what)
        if self.clock is not None:
            self.clock.advance(1)
        if self.kind is not None:
            msg = f"challenge {self.kind}"
            raise SourceError(msg, self.kind)

    def prepare(self, cand: Candidate) -> None:
        if self.fail_prepare:
            msg = "no such extension"
            raise SourceError(msg)

    def popular(self, cand: Candidate) -> list[Hit]:
        return []

    def search(self, cand: Candidate, query: str) -> list[Hit]:
        self._tick(f"search {query}")
        library = {"Alpha Story": "a", "Beta": "b", "Ganma": "g", "Delta": "d"}
        return [Hit(t, r) for t, r in library.items() if t == query]

    def chapters(self, cand: Candidate, hit: Hit) -> list[Chapter]:
        self._tick(f"chapters {hit.ref}")
        if hit.ref == "d":
            return []
        if hit.ref == "b":
            msg = "HTTP 500"
            raise SourceError(msg)
        return [Chapter(f"{hit.ref}{i}", float(i // 2)) for i in range(12)]

    def pages(self, cand: Candidate, chapter: Chapter) -> list[PageImage]:
        self._tick(f"pages {chapter.ref}")
        if chapter.ref.startswith("g"):
            msg = "CEF is disabled"
            raise SourceError(msg, "webview")
        return [PageImage(f"https://img/{i}") for i in range(5)]

    def image(self, cand: Candidate, page: PageImage) -> bytes:
        self._tick(f"image {page.url}")
        return fixture_bytes("page.webp")


def test_full_evaluation_and_metrics(tmp_path: Path) -> None:
    clock = FakeClock()
    state = RunDir(tmp_path, "t").source(CAND.id)
    backend: Backend = FakeBackend()
    assert evaluate(CAND, backend, state, PLAN, Deadline(clock, None))
    assert evaluate(CAND, backend, state, PLAN, Deadline(clock, None))  # already done
    assert set(state.found()) == {"r1", "r2", "r3", "r4"}
    assert state.chapters["r1"] == {"count": 6, "ratio": 0.6, "pick": "a6"}
    assert state.chapters["r2"]["error"] == "HTTP 500"
    assert state.chapters["r3"]["ratio"] == 1.0
    assert isinstance(backend, FakeBackend)
    assert "search Gamma" in backend.calls  # first title tried, then the alt
    assert (
        cast("list[dict[str, object]]", state.images["r1"]["pages"])[0]["fmt"] == "WEBP"
    )
    assert state.images["r3"]["kind"] == "webview"
    state.observe(Observation(clock.now(), "fake.test", True, 120.0, None, 200))
    state.observe(Observation(clock.now(), "fake.test", False, 900.0, "webview", 200))
    state.save()
    probes = [Observation(clock.now() - 10, "fake.test", True, 300.0, None, 200)]
    m = metrics(
        CAND, RunDir(tmp_path, "t").source(CAND.id), MANIFEST, probes, clock.now()
    )
    assert m["coverage"] == {
        "referenceSize": 4,
        "found": 4,
        "ratio": 1.0,
        "complete": None,  # a legacy manifest: no merged coverage
        "completeRatio": None,
    }
    # Every found title has a chapter list: r4 has none (ratio 0).
    assert m["chapterCompleteness"] == {"sampled": 3, "medianRatio": 0.6}
    assert m["imageQuality"] == {
        "sampledPages": 2,
        "medianWidthPx": 120,
        "medianJpegQuality": None,
    }
    assert m["blocking"] == {
        "challengeRate": 0.333,
        "kinds": ["webview"],
        "hardRate": 0.0,
    }
    assert m["unreachable"] is False
    assert (m["pkg"], m["plugin"]) == (None, None)
    assert m["flags"] == ["needs-browser-engine"]
    assert m["latencyMs"] == {"p50": 300, "p95": 900}
    assert cast("dict[str, object]", m["uptime"])["status"] == "accruing"
    assert m["availability"] == {
        "native": False,
        "mangayomiJs": False,
        "keiyoushi": False,
    }


def test_every_found_title_gets_a_chapter_list(tmp_path: Path) -> None:
    """The merged coverage metric needs every found title's chapter count.

    Whatever the legacy manifest ``completeness`` says.
    """
    state = RunDir(tmp_path, "t").source(CAND.id)
    plan = Plan(REFS, Manifest(["r1", "r2", "r3", "r4"], 1, 2, 2))
    assert evaluate(CAND, FakeBackend(), state, plan, Deadline(FakeClock(), None))
    assert set(state.chapters) == {"r1", "r2", "r3", "r4"}


def test_budget_stops_and_resumes(tmp_path: Path) -> None:
    clock = FakeClock()
    run = RunDir(tmp_path, "t")
    backend = FakeBackend(clock=clock)
    rounds = 0
    while not evaluate(CAND, backend, run.source(CAND.id), PLAN, Deadline(clock, 1.5)):
        rounds += 1
    assert rounds >= 3
    assert run.source(CAND.id).done
    assert run.evaluated_ids() == [CAND.id]


def test_blocked_source_aborts_early(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "t").source(CAND.id)
    assert evaluate(
        CAND,
        FakeBackend(kind="cloudflare"),
        state,
        PLAN,
        Deadline(FakeClock(), None),
    )
    assert state.aborted == "blocking"
    assert len(state.titles) == 3


def test_webview_source_does_not_abort(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "t").source(CAND.id)
    assert evaluate(
        CAND,
        FakeBackend(kind="webview"),
        state,
        PLAN,
        Deadline(FakeClock(), None),
    )
    assert state.aborted is None
    assert len(state.titles) == len(PLAN.manifest.sample)


def test_dead_source_aborts_after_five(tmp_path: Path) -> None:
    refs = {f"k{i}": RefTitle(f"k{i}", (f"T{i}",)) for i in range(7)}
    manifest = Manifest(list(refs), 3, 2, 2)

    class Dead(FakeBackend):
        def search(self, cand: Candidate, query: str) -> list[Hit]:
            msg = "connection refused"
            raise SourceError(msg)

    state = RunDir(tmp_path, "t").source(CAND.id)
    assert evaluate(
        CAND, Dead(), state, Plan(refs, manifest), Deadline(FakeClock(), None)
    )
    assert state.aborted == "unreachable"
    assert len(state.titles) == 5


def test_unavailable_source_is_unmeasured(tmp_path: Path) -> None:
    state = RunDir(tmp_path, "t").source(CAND.id)
    assert evaluate(
        CAND,
        FakeBackend(fail_prepare=True),
        state,
        PLAN,
        Deadline(FakeClock(), None),
    )
    assert state.aborted == "unavailable"
    m = metrics(CAND, state, MANIFEST, [], 0.0)
    assert m["coverage"] == {
        "referenceSize": 4,
        "found": None,
        "ratio": None,
        "complete": None,
        "completeRatio": None,
    }
    assert m["blocking"] == {"challengeRate": 0.0, "kinds": [], "hardRate": 0.0}
    assert m["flags"] == []
    assert m["latencyMs"] == {"p50": None, "p95": None}


def test_percentile_and_empty_run(tmp_path: Path) -> None:
    assert percentile([], 50) is None
    assert percentile([5.0, 1.0, 3.0], 50) == 3.0
    assert RunDir(tmp_path, "none").evaluated_ids() == []
    assert Manifest.load(tmp_path / "missing.json") is None
    empty = Manifest([], 1, 1, 1)
    m = metrics(CAND, RunDir(tmp_path, "t").source("x"), empty, [], 0.0)
    assert cast("dict[str, object]", m["coverage"])["ratio"] is None
