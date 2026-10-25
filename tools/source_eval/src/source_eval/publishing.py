# Copyright (c) 2026 Krzysztof Rudnicki
"""``report [--publish]`` as resumable < 60 s batches.

Building the report is local and quick (about 1 s for 766 sources), so every
call rebuilds it and rewrites the output file. Publishing is RTDB
writes, records (in chunks) then meta; each is a step that starts only when its worst
case (``RTDB_STEP``) fits in the budget, and each finished step is
remembered in ``runs/<run>/publish.json`` until both are done. A finished
publish also leaves the run's hard cuts (``hard_cut.json``) for the next
run's re-probe; that file naming the run is also the "already published"
marker ``published`` reads.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, cast

from source_eval.budget import MORE_WORK
from source_eval.candidates import catalog
from source_eval.fsio import read_json, write_json_atomic
from source_eval.report import META_PATH, RTDB_PATH, build_report
from source_eval.score import HARD_CODES
from source_eval.state import sha1

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from source_eval.app import App
    from source_eval.profile import Profile
    from source_eval.report import RtdbWriter
    from source_eval.score import Record
    from source_eval.state import Manifest, RunDir

#: The last published run's hard cuts, in the state dir.
HARD_CUT_FILE = "hard_cut.json"
#: Worst case of one RTDB write: token refresh + request, both bounded
#: (``report.TOKEN_TIMEOUT`` + ``report.RTDB_TIMEOUT``).
RTDB_STEP = 20.0
#: Records per RTDB write.
CHUNK = 200


def hard_cut_ids(report: dict[str, object]) -> list[str]:
    """Ids of the records whose cut reasons include a hard-filter code."""
    return [
        str(r["id"])
        for r in cast("list[Record]", report["sources"])
        if HARD_CODES.intersection(cast("list[str]", r.get("cutReasons") or []))
    ]


def previous_hard_cuts(
    state_dir: Path, run_id: str, *, wanted: bool = True
) -> tuple[list[str], str | None]:
    """``(ids, run)`` hard-cut by the last published run, unless it is ``run_id``.

    Nothing when not ``wanted`` (``init-run`` without ``--reprobe``).
    """
    data = read_json(state_dir / HARD_CUT_FILE, {}) if wanted else {}
    prev = data.get("runId") if isinstance(data, dict) else None
    if prev in (None, run_id):
        return [], None
    ids = cast("dict[str, list[object]]", data)["ids"]
    return [str(i) for i in ids], str(prev)


def published_cmd(state_dir: Path, run_id: str, out: Callable[[str], None]) -> int:
    """``published``: 0 when ``run_id`` finished its publish, else ``MORE_WORK``.

    The marker is ``hard_cut.json`` naming ``run_id``: ``report_cmd`` writes
    it only after the last RTDB step, so an interrupted publish (or one never
    started) cannot have it. weekly.sh skips a published week, which a
    ``Persistent=true`` timer would otherwise rerun and re-publish.
    """
    data = read_json(state_dir / HARD_CUT_FILE, {})
    done = isinstance(data, dict) and data.get("runId") == run_id
    out(f"published: {run_id} {'yes' if done else 'not yet'}")
    return 0 if done else MORE_WORK


def publish_steps(
    report: dict[str, object],
) -> list[tuple[str, str, dict[str, object]]]:
    """``(name, path, data)`` RTDB writes: records in chunks, then the meta.

    Chunks of ``CHUNK`` records by RTDB key, so each write stays small (one
    ~0.7 MB PATCH could outlast ``RTDB_TIMEOUT`` on a slow uplink) and a
    chunk holds the same sources however often the report is rebuilt.
    """
    records = sorted(
        (sha1(str(r["id"])), r) for r in cast("list[Record]", report["sources"])
    )
    steps: list[tuple[str, str, dict[str, object]]] = [
        (f"records-{n // CHUNK}", RTDB_PATH, dict(records[n : n + CHUNK]))
        for n in range(0, len(records), CHUNK)
    ]
    return [*steps, ("meta", META_PATH, cast("dict[str, object]", report["meta"]))]


def report_cmd(  # noqa: PLR0913, PLR0917 -- one argument per input it joins
    app: App,
    run: RunDir,
    manifest: Manifest,
    out: Path,
    writer: RtdbWriter | None,
    profile: Profile,
    budget: float | None,
) -> int:
    """Write the ranked report; with ``writer``, publish what is still due."""
    deadline, _ = app.limits(budget)
    cands = {c.id: c for c in catalog.load(app.candidates_path)}
    report = build_report(
        cands,
        run,
        manifest,
        app.uptime,
        app.clock.now(),
        skipped=catalog.load_skipped(app.skipped_path),
        profile=profile,
    )
    write_json_atomic(out, report)
    app.out(f"profile: {profile.name}")
    count = len(cast("list[object]", report["sources"]))
    app.out(f"report: {count} sources -> {out}")
    if writer is None:
        return 0
    progress_path = run.root / "publish.json"
    progress = cast("dict[str, bool]", read_json(progress_path, {}))
    for name, path, data in publish_steps(report):
        if progress.get(name):
            continue
        if deadline.remaining() - app.s.grace < RTDB_STEP:
            app.out(f"publish: budget spent before {name}, continuing next call")
            return MORE_WORK
        writer.patch(path, data)
        progress[name] = True
        write_json_atomic(progress_path, progress)
    progress_path.unlink(missing_ok=True)
    ids = hard_cut_ids(report)
    write_json_atomic(
        app.s.state_dir / HARD_CUT_FILE, {"runId": run.run_id, "ids": ids}
    )
    app.out(f"published: {count} records; {len(ids)} hard cuts to re-probe next run")
    return 0
