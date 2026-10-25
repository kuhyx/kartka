# Copyright (c) 2026 Krzysztof Rudnicki
"""Wiring: settings, shared politeness state, and one function per command.

A network command's ``budget`` (s since process start) is a hard wall-clock
limit; ``MORE_WORK`` (exit 10) means "call me again": state is on disk.
"""

from __future__ import annotations

from dataclasses import replace
from typing import TYPE_CHECKING

from source_eval import runner
from source_eval.backends.mangadex import MangaDexBackend
from source_eval.backends.plugin import PluginBackend
from source_eval.backends.suwayomi import SuwayomiBackend
from source_eval.budget import (
    MORE_WORK,
    BudgetExhausted,
    Deadline,
    RequestBudget,
    stratified,
    within,
)
from source_eval.cache import DiskCache
from source_eval.candidates import catalog
from source_eval.gate import HostGate
from source_eval.polite import USER_AGENT, PoliteClient
from source_eval.profile import DEFAULT, Profile
from source_eval.publishing import previous_hard_cuts, report_cmd
from source_eval.ramp import Ramp, ramp_finish, ramp_start
from source_eval.reference.build import (
    Reference,
    build,
    enrich_chapters,
    load_sy_titles,
)
from source_eval.state import Manifest, RunDir
from source_eval.uptime import UptimeLog

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path
    import threading

    from source_eval.backends.base import Backend
    from source_eval.http import Clock, Transport
    from source_eval.models import Candidate
    from source_eval.polite import Observation
    from source_eval.report import RtdbWriter
    from source_eval.settings import Settings

__all__ = ["MORE_WORK", "App"]
USAGE = 2  # exit code of a usage error (``init-run --ramp`` before ``ramp start``)


class App:
    """Holds the shared gate/cache so concurrent clients stay polite together."""

    def __init__(
        self,
        settings: Settings,
        clock: Clock,
        transport: Transport,
        out: Callable[[str], None],
        started: float | None = None,
    ) -> None:
        """Create the shared politeness state; budgets count from ``started``."""
        self.s = settings
        self.clock = clock
        self.transport = transport
        self.out = out
        self.started = started
        self.gate = HostGate(
            settings.state_dir / "hosts.json", settings.interval, clock
        )
        self.cache = DiskCache(settings.cache_dir, settings.cache_ttl, clock)
        self.uptime = UptimeLog(settings.state_dir / "uptime")

    def limits(self, budget: float | None) -> tuple[Deadline, RequestBudget]:
        """``budget`` s from process start (from now in tests), per request too."""
        deadline = Deadline(self.clock, budget, start=self.started)
        return deadline, RequestBudget(deadline, self.s.min_start, self.s.grace)

    def client(
        self,
        observe: Callable[[Observation], None] | None = None,
        budget: RequestBudget | None = None,
        inflight: threading.Semaphore | None = None,
    ) -> PoliteClient:
        """A client sharing the gate and cache, reporting to ``observe``."""
        return PoliteClient(
            self.transport,
            self.gate,
            self.clock,
            self.cache,
            USER_AGENT,
            observe=observe,
            budget=budget,
            inflight=inflight,
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

    @property
    def skipped_path(self) -> Path:
        """``data/candidates_skipped.json``: index entries the merge dropped."""
        return self.s.data_dir / "candidates_skipped.json"

    def reference(self) -> Reference:
        """``data/reference.json``."""
        return Reference(self.s.data_dir / "reference.json", self.clock)

    def select(self, ids: list[str], *, installed: bool) -> list[Candidate]:
        """Candidates by id, plus kuhy's installed set when asked; [] = all."""
        cands = catalog.load(self.candidates_path)
        if not ids and not installed:
            return cands
        return [c for c in cands if c.id in ids or (installed and c.installed)]

    def cmd_candidates(self, budget: float | None = None) -> int:
        """Refresh ``data/candidates.json`` from both indexes."""
        client = self.client(budget=self.limits(budget)[1])
        try:
            cands, skipped = catalog.fetch_candidates(
                client, self.s.data_dir / "legacy_sources.json"
            )
        except BudgetExhausted:
            self.out("candidates: budget spent, continuing next call")
            return MORE_WORK
        catalog.save(self.candidates_path, cands)
        catalog.save_skipped(self.skipped_path, skipped)
        for row in skipped:
            self.out(f"skipped {row['index']} {row['reason']}: {row['count']}")
        self.out(f"candidates: {len(cands)}")
        return 0

    def cmd_reference(self, budget: float | None, top: int) -> int:
        """Advance the reference build."""
        ref = self.reference()
        sy = load_sy_titles(self.s.data_dir / "sy_titles.json")
        deadline, per_request = self.limits(budget)
        client = self.client(budget=per_request)
        done = within(lambda: build(client, ref, sy, deadline, top=top))
        self.out(f"reference: {len(ref.titles)} titles, complete={done}")
        return 0 if done else MORE_WORK

    def cmd_init_run(
        self,
        run_id: str,
        sample: int | None,
        steps: Manifest,
        *,
        ramp: bool = False,
        reprobe: bool = False,
    ) -> int:
        """Fix the run's reference sample (``sample`` titles, None = all).

        ``steps`` carries the per-step sizes; its own ``sample`` is ignored.
        ``ramp`` takes the size from ``ramp start``; ``reprobe`` lists the
        previous published run's hard cuts for a re-probe. Idempotent: an
        existing run keeps its manifest.
        """
        if ramp:
            sample = self._ramp().current_sample(run_id)
            if sample is None:
                self.out(f"run {run_id}: no ramp; call 'ramp start --run {run_id}'")
                return USAGE
        run = RunDir(self.s.state_dir, run_id)
        if Manifest.load(run.manifest_path) is None:
            keys = stratified([t.key for t in self.reference().titles], sample)
            ids, prev = previous_hard_cuts(self.s.state_dir, run_id, wanted=reprobe)
            replace(steps, sample=keys, reprobe=ids, reprobe_from=prev).save(
                run.manifest_path
            )
        self.out(f"run {run_id}: ready")
        return 0

    def _manifest(self, run_id: str) -> tuple[RunDir, Manifest]:
        return RunDir.open(self.s.state_dir, run_id)

    def cmd_enrich(self, run_id: str, budget: float | None) -> int:
        """MangaUpdates chapter counts for the run's sample."""
        _, manifest = self._manifest(run_id)
        deadline, per_request = self.limits(budget)
        client, ref = self.client(budget=per_request), self.reference()
        done = within(lambda: enrich_chapters(client, ref, manifest.sample, deadline))
        self.out(f"enrich: complete={done}")
        return 0 if done else MORE_WORK

    def probe_one(self, cand: Candidate) -> Observation:
        """One uptime probe of ``cand`` (see :mod:`source_eval.uptime`)."""
        return runner.probe_one(self, cand, None)

    def cmd_probe(
        self,
        cands: list[Candidate],
        workers: int,
        budget: float | None = None,
        fresh: float | None = None,
    ) -> int:
        """One uptime probe per candidate not probed within ``fresh`` seconds."""
        return runner.probe_all(self, cands, workers, budget, fresh)

    def cmd_run(
        self,
        run_id: str,
        cands: list[Candidate],
        budget: float | None,
        workers: int,
        inflight: int = 64,
    ) -> int:
        """Advance every selected source; exit MORE_WORK if any is unfinished."""
        run, manifest = self._manifest(run_id)
        return runner.run_all(self, run, manifest, cands, (budget, workers, inflight))

    def cmd_report(
        self,
        run_id: str,
        out: Path,
        writer: RtdbWriter | None,
        profile: Profile = DEFAULT,
        budget: float | None = None,
    ) -> int:
        """Write the ranked report; publish it (resumably) with a writer."""
        run, manifest = self._manifest(run_id)
        return report_cmd(self, run, manifest, out, writer, profile, budget)

    def cmd_ramp_start(self, run_id: str, sample: int | None) -> int:
        """Start (or resume) ``run_id`` on the ramp and log its sample."""
        return ramp_start(self._ramp(), run_id, sample, self.out)

    def cmd_ramp_finish(self, run_id: str) -> int:
        """Record ``run_id``'s wall time for the next run's ramp."""
        return ramp_finish(self._ramp(), run_id, self.out)

    def _ramp(self) -> Ramp:
        return Ramp(self.s.state_dir / "ramp.json", self.clock)
