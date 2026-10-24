# Copyright (c) 2026 Krzysztof Rudnicki
"""Wiring: settings, shared politeness state, and one function per command."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
import os
from pathlib import Path
from typing import TYPE_CHECKING

from source_eval.backends.mangadex import MangaDexBackend
from source_eval.backends.plugin import PluginBackend
from source_eval.backends.suwayomi import SuwayomiBackend, SuwayomiConfig
from source_eval.budget import Deadline, stratified
from source_eval.cache import DiskCache
from source_eval.candidates import catalog
from source_eval.evaluate import evaluate
from source_eval.fsio import write_json_atomic
from source_eval.http import TransportError
from source_eval.models import SourceError
from source_eval.polite import HostGate, Observation, PoliteClient
from source_eval.reference.build import (
    Reference,
    build,
    enrich_chapters,
    load_sy_titles,
)
from source_eval.report import build_report, publish
from source_eval.state import Manifest, RunDir
from source_eval.uptime import UptimeLog, failed, probe_front_page

if TYPE_CHECKING:
    from collections.abc import Callable

    from source_eval.backends.base import Backend
    from source_eval.http import Clock, Transport
    from source_eval.models import Candidate
    from source_eval.report import RtdbWriter

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
USER_AGENT = (
    "kartka-source-eval/0.1 (+https://github.com/kuhyx/kartka; polite: 1 req/2s/host)"
)
#: Exit code when the budget ran out and another call should continue.
MORE_WORK = 10


def _xdg(var: str, fallback: str) -> Path:
    return Path(os.environ.get(var) or Path.home() / fallback) / "kartka-source-eval"


@dataclass(frozen=True, slots=True)
class Settings:
    """Paths and knobs; every default can be overridden on the command line."""

    data_dir: Path = PACKAGE_ROOT / "data"
    out_dir: Path = PACKAGE_ROOT / "out"
    state_dir: Path = field(
        default_factory=lambda: _xdg("XDG_STATE_HOME", ".local/state")
    )
    cache_dir: Path = field(default_factory=lambda: _xdg("XDG_CACHE_HOME", ".cache"))
    interval: float = 2.0
    cache_ttl: float = 6 * 86400.0
    suwayomi: SuwayomiConfig = field(default_factory=SuwayomiConfig)


class App:
    """Holds the shared gate/cache so concurrent clients stay polite together."""

    def __init__(
        self,
        settings: Settings,
        clock: Clock,
        transport: Transport,
        out: Callable[[str], None],
    ) -> None:
        """Create the shared politeness state."""
        self.s = settings
        self.clock = clock
        self.transport = transport
        self.out = out
        self.gate = HostGate(
            settings.state_dir / "hosts.json", settings.interval, clock
        )
        self.cache = DiskCache(settings.cache_dir, settings.cache_ttl, clock)
        self.uptime = UptimeLog(settings.state_dir / "uptime")

    def client(
        self, observe: Callable[[Observation], None] | None = None
    ) -> PoliteClient:
        """A client sharing the gate and cache, reporting to ``observe``."""
        return PoliteClient(
            self.transport,
            self.gate,
            self.clock,
            self.cache,
            USER_AGENT,
            observe=observe,
        )

    def backend(self, cand: Candidate, client: PoliteClient) -> Backend:
        """The backend that reads ``cand`` the way Kartka would."""
        if cand.origin == "native":
            return MangaDexBackend(client)
        if cand.origin == "suwayomi":
            return SuwayomiBackend(client, self.s.suwayomi)
        return PluginBackend()

    @property
    def candidates_path(self) -> Path:
        """``data/candidates.json``."""
        return self.s.data_dir / "candidates.json"

    def reference(self) -> Reference:
        """``data/reference.json``."""
        return Reference(self.s.data_dir / "reference.json", self.clock)

    def select(self, ids: list[str], *, installed: bool) -> list[Candidate]:
        """Candidates by id, plus kuhy's installed set when asked; [] = all."""
        cands = catalog.load(self.candidates_path)
        if not ids and not installed:
            return cands
        return [c for c in cands if c.id in ids or (installed and c.installed)]

    def cmd_candidates(self) -> int:
        """Refresh ``data/candidates.json`` from both indexes."""
        cands = catalog.fetch_candidates(self.client(), self.s.data_dir / "legacy_sources.json")
        catalog.save(self.candidates_path, cands)
        self.out(f"candidates: {len(cands)}")
        return 0

    def cmd_reference(self, budget: float | None, top: int) -> int:
        """Advance the reference build."""
        ref = self.reference()
        sy = load_sy_titles(self.s.data_dir / "sy_titles.json")
        done = build(self.client(), ref, sy, Deadline(self.clock, budget), top=top)
        self.out(f"reference: {len(ref.titles)} titles, complete={done}")
        return 0 if done else MORE_WORK

    def cmd_init_run(
        self,
        run_id: str,
        sample: int | None,
        completeness: int,
        images: int,
        pages: int,
    ) -> int:
        """Fix the run's reference sample and step sizes (idempotent)."""
        run = RunDir(self.s.state_dir, run_id)
        if Manifest.load(run.manifest_path) is None:
            keys = stratified([t.key for t in self.reference().titles], sample)
            Manifest(keys, completeness, images, pages).save(run.manifest_path)
        self.out(f"run {run_id}: ready")
        return 0

    def _manifest(self, run_id: str) -> tuple[RunDir, Manifest]:
        run = RunDir(self.s.state_dir, run_id)
        manifest = Manifest.load(run.manifest_path)
        if manifest is None:
            msg = f"run {run_id} has no manifest; run init-run first"
            raise SystemExit(msg)
        return run, manifest

    def cmd_enrich(self, run_id: str, budget: float | None) -> int:
        """MangaUpdates chapter counts for the run's sample."""
        _, manifest = self._manifest(run_id)
        ref = self.reference()
        done = enrich_chapters(
            self.client(), ref, manifest.sample, Deadline(self.clock, budget)
        )
        self.out(f"enrich: complete={done}")
        return 0 if done else MORE_WORK

    def probe_one(self, cand: Candidate) -> Observation:
        """One uptime probe of ``cand`` (see :mod:`source_eval.uptime`)."""
        if cand.origin == "plugin":
            obs = probe_front_page(self.client(), self.clock, cand.host, cand.base_url)
        else:
            seen: list[Observation] = []
            backend = self.backend(cand, self.client(observe=seen.append))
            try:
                backend.prepare(cand)
                backend.popular(cand)
            except TransportError:
                seen.append(failed(self.clock, cand.host))
            except SourceError:
                pass
            obs = seen[-1] if seen else Observation(self.clock.now(), cand.host, False, 0.0, None, None)
        self.uptime.append(cand.id, obs)
        return obs

    def cmd_probe(self, cands: list[Candidate], workers: int) -> int:
        """One uptime probe per candidate, in parallel (pacing is per host)."""
        with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
            results = list(pool.map(self.probe_one, cands))
        for cand, obs in zip(cands, results, strict=True):
            self.out(f"probe {cand.id} ({cand.name}): ok={obs.ok} kind={obs.kind} status={obs.status}")
        self.out(f"probe: {sum(1 for r in results if r.ok)}/{len(results)} ok")
        return 0

    def cmd_run(
        self, run_id: str, cands: list[Candidate], budget: float | None, workers: int
    ) -> int:
        """Advance every selected source; exit MORE_WORK if any is unfinished."""
        run, manifest = self._manifest(run_id)
        refs = {t.key: t for t in self.reference().titles}
        deadline = Deadline(self.clock, budget)

        def one(cand: Candidate) -> bool:
            state = run.source(cand.id)
            client = self.client(observe=state.observe)
            done = evaluate(
                cand, self.backend(cand, client), state, refs, manifest, deadline
            )
            self.out(
                f"{cand.id} ({cand.name}): {'done' if done else 'partial'} titles={len(state.titles)}/{len(manifest.sample)}"
            )
            return done

        with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
            finished = list(pool.map(one, cands))
        return 0 if all(finished) else MORE_WORK

    def cmd_report(self, run_id: str, out: Path, writer: RtdbWriter | None) -> int:
        """Write the ranked report; publish it when a writer is given."""
        run, manifest = self._manifest(run_id)
        cands = {c.id: c for c in catalog.load(self.candidates_path)}
        report = build_report(
            cands, run, run_id, manifest, self.uptime, self.clock.now()
        )
        write_json_atomic(out, report)
        self.out(f"report: {len(report['sources'])} sources -> {out}")  # type: ignore[arg-type]
        if writer is not None:
            self.out(f"published: {publish(report, writer)} records")
        return 0
