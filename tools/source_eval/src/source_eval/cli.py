# Copyright (c) 2026 Krzysztof Rudnicki
"""``source-eval`` command line. Every long step takes ``--budget`` seconds and
exits 10 when another call should continue (state is on disk).
"""

from __future__ import annotations

import argparse
from dataclasses import replace
import os
from pathlib import Path
import sys
from typing import TYPE_CHECKING

from source_eval.app import App, Settings
from source_eval.backends.suwayomi import SuwayomiConfig
from source_eval.http import RequestsTransport, SystemClock
from source_eval.report import firebase_writer

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

    from source_eval.report import RtdbWriter


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="source-eval", description=__doc__)
    p.add_argument("--state-dir", type=Path)
    p.add_argument("--data-dir", type=Path)
    p.add_argument(
        "--suwayomi-url",
        default=os.environ.get("KARTKA_SUWAYOMI_URL", "http://127.0.0.1:4567"),
    )
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("candidates", help="refresh data/candidates.json")
    ref = sub.add_parser("reference", help="build data/reference.json (resumable)")
    ref.add_argument("--top", type=int, default=500)
    init = sub.add_parser("init-run", help="fix a run's reference sample")
    init.add_argument("--sample", type=int, default=None, help="titles (default: all)")
    init.add_argument("--completeness", type=int, default=40)
    init.add_argument("--images", type=int, default=10)
    init.add_argument("--pages", type=int, default=3)
    sub.add_parser("enrich", help="MangaUpdates chapter counts for the run sample")
    probe = sub.add_parser("probe", help="one uptime probe per host")
    run = sub.add_parser("run", help="measure sources (resumable)")
    rep = sub.add_parser("report", help="write the ranked report")
    rep.add_argument("--out", type=Path)
    rep.add_argument(
        "--publish", action="store_true", help="also write RTDB /kartka/source_health"
    )
    for cmd in (init, run, rep, sub.choices["enrich"]):
        cmd.add_argument("--run", dest="run_id", default="weekly")
    for cmd in (ref, run, sub.choices["enrich"]):
        cmd.add_argument(
            "--budget", type=float, default=None, help="seconds before a clean stop"
        )
    for cmd in (probe, run):
        cmd.add_argument("--ids", nargs="*", default=[])
        cmd.add_argument(
            "--installed", action="store_true", help="add kuhy's installed set"
        )
        cmd.add_argument("--workers", type=int, default=16)
    return p


def _settings(args: argparse.Namespace) -> Settings:
    s = Settings(
        suwayomi=SuwayomiConfig(
            args.suwayomi_url.rstrip("/"),
            os.environ.get("KARTKA_SUWAYOMI_USER", ""),
            os.environ.get("KARTKA_SUWAYOMI_PASS", ""),
        )
    )
    if args.state_dir:
        s = replace(s, state_dir=args.state_dir)
    if args.data_dir:
        s = replace(s, data_dir=args.data_dir)
    return s


def dispatch(
    app: App, args: argparse.Namespace, writer: Callable[[], RtdbWriter]
) -> int:
    """Run the parsed command against ``app``."""
    match args.cmd:
        case "candidates":
            return app.cmd_candidates()
        case "reference":
            return app.cmd_reference(args.budget, args.top)
        case "init-run":
            return app.cmd_init_run(
                args.run_id, args.sample, args.completeness, args.images, args.pages
            )
        case "enrich":
            return app.cmd_enrich(args.run_id, args.budget)
        case "probe":
            return app.cmd_probe(
                app.select(args.ids, installed=args.installed), args.workers
            )
        case "run":
            cands = app.select(args.ids, installed=args.installed)
            return app.cmd_run(args.run_id, cands, args.budget, args.workers)
        case _:
            out = args.out or app.s.out_dir / "latest.json"
            return app.cmd_report(args.run_id, out, writer() if args.publish else None)


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point."""
    args = _parser().parse_args(argv)

    def emit(line: str) -> None:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    app = App(_settings(args), SystemClock(), RequestsTransport(), emit)
    return dispatch(app, args, firebase_writer)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
