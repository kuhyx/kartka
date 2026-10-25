# Copyright (c) 2026 Krzysztof Rudnicki
"""``run`` and ``probe``: many sources at once, one budget, polite per host.

Speed comes from parallelism across hosts (kuhy, 2026-10-25): the 2 s
per-host interval stays. Sources are grouped by host and each group is one
lane, worked serially, so no two lanes ever queue on the same host's gate;
``workers`` lanes run at once and at most ``inflight`` requests are in the
air (the eval server queues the rest itself, inflating the latency it
reports for the source).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import threading
import time
from typing import TYPE_CHECKING

from source_eval.budget import MORE_WORK, BudgetExhausted
from source_eval.evaluate import Plan, evaluate
from source_eval.http import TransportError
from source_eval.models import SourceError
from source_eval.polite import Observation
from source_eval.uptime import failed, lookup_window, probe_front_page

if TYPE_CHECKING:
    from source_eval.app import App
    from source_eval.budget import RequestBudget
    from source_eval.models import Candidate
    from source_eval.state import Manifest, RunDir


class _Tally:
    """Live requests observed this invocation (thread-safe)."""

    def __init__(self) -> None:
        self.count = 0
        self._lock = threading.Lock()

    def tick(self) -> None:
        with self._lock:
            self.count += 1


def by_host(cands: list[Candidate]) -> list[list[Candidate]]:
    """Candidates grouped by upstream host, in first-seen order."""
    groups: dict[str, list[Candidate]] = {}
    for cand in cands:
        groups.setdefault(cand.host, []).append(cand)
    return list(groups.values())


def run_all(
    app: App,
    run: RunDir,
    manifest: Manifest,
    cands: list[Candidate],
    knobs: tuple[float | None, int, int],
) -> int:
    """Advance every source within the budget; MORE_WORK while any is unfinished.

    ``knobs`` is ``(budget, workers, inflight)``. Prints one line per source
    it advanced and a summary with the request rate and CPU time.
    """
    budget, workers, inflight = knobs
    began, cpu = app.clock.now(), time.process_time()
    plan = Plan({t.key: t for t in app.reference().titles}, manifest)
    deadline, per_request = app.limits(budget)
    slots = threading.Semaphore(max(1, inflight))
    tally = _Tally()
    done: list[str] = []

    def one(cand: Candidate) -> bool:
        state = run.source(cand.id)
        if state.done:
            done.append(cand.id)
            return True

        def observe(obs: Observation) -> None:
            state.observe(obs)
            tally.tick()

        client = app.client(observe=observe, budget=per_request, inflight=slots)
        before = len(state.observations)
        finished = evaluate(cand, app.backend(cand, client), state, plan, deadline)
        if finished or len(state.observations) > before:  # quiet when untouched
            progress = f"titles={len(state.titles)}/{len(manifest.sample)}"
            word = "done" if finished else "partial"
            app.out(f"{cand.id} ({cand.name}): {word} {progress}")
        if finished:
            done.append(cand.id)
        return finished

    def lane(group: list[Candidate]) -> bool:
        return all(one(cand) for cand in group)  # stops at the first unfinished

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        finished = list(pool.map(lane, by_host(cands)))
    app.gate.flush()
    wall = max(app.clock.now() - began, 1e-9)
    app.out(
        f"run: {len(done)}/{len(cands)} sources done; {tally.count} requests in"
        f" {wall:.1f} s ({tally.count / wall:.1f}/s);"
        f" cpu {time.process_time() - cpu:.1f} s"
    )
    return 0 if all(finished) else MORE_WORK


def probe_one(app: App, cand: Candidate, budget: RequestBudget | None) -> Observation:
    """One uptime probe of ``cand`` (see :mod:`source_eval.uptime`).

    Raises:
        BudgetExhausted: Not enough budget for it; nothing is logged.
    """
    if cand.origin == "plugin":
        client = app.client(budget=budget)
        obs = probe_front_page(
            client, app.clock, cand.host, cand.base_url, budget=budget
        )
    else:
        seen: list[Observation] = []
        backend = app.backend(cand, app.client(observe=seen.append, budget=budget))
        try:
            backend.prepare(cand)
            backend.popular(cand)
        except TransportError:
            seen.append(failed(app.clock, cand.host, within=lookup_window(budget)))
        except SourceError:
            pass
        obs = seen[-1] if seen else Observation.failure(app.clock.now(), cand.host)
    app.uptime.append(cand.id, obs)
    return obs


def _fresh(app: App, cand: Candidate, fresh: float | None) -> bool:
    if fresh is None:
        return False
    last = app.uptime.last(cand.id)
    return last is not None and last.at >= app.clock.now() - fresh


def probe_all(
    app: App,
    cands: list[Candidate],
    workers: int,
    budget: float | None,
    fresh: float | None,
) -> int:
    """Probe every candidate not probed within ``fresh`` seconds, in budget.

    MORE_WORK when the budget stopped any probe; the next call skips the
    ones already done this round (``fresh``).
    """
    _, per_request = app.limits(budget)
    todo = [c for c in cands if not _fresh(app, c, fresh)]

    def one(cand: Candidate) -> Observation | None:
        try:
            return probe_one(app, cand, per_request)
        except BudgetExhausted:
            return None

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        results = list(pool.map(one, todo))
    app.gate.flush()
    probed = [(c, r) for c, r in zip(todo, results, strict=True) if r is not None]
    for cand, obs in probed:
        verdict = f"ok={obs.ok} kind={obs.kind} status={obs.status}"
        app.out(f"probe {cand.id} ({cand.name}): {verdict}")
    if len(todo) < len(cands):
        app.out(f"probe: {len(cands) - len(todo)} fresh (probed this round), skipped")
    app.out(f"probe: {sum(1 for _, r in probed if r.ok)}/{len(probed)} ok")
    return MORE_WORK if len(probed) < len(todo) else 0
