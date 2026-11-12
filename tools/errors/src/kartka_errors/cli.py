# Copyright (c) 2026 Krzysztof Rudnicki
"""``kartka-errors ingest | resolve <sig>... | render``.

``ingest`` reads ``/kartka-e2e/errors`` (each report sealed by the app,
opened here with the shared crdt-sync password), merges every report into the local
state (saved before anything is deleted, so a crash loses nothing),
rewrites the fixme report, then deletes exactly the entries it read, one
``device/id`` path at a time (never the whole node: that would race with
a device uploading right now). ``--keep`` skips the delete.

Exit codes: 0 done, 1 RTDB failure or unknown signature, 3 no session,
4 e2e locked (no or wrong crdt-sync password: nothing read or deleted).
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import datetime as dt
import fcntl
import os
from pathlib import Path
import sys
from typing import cast
lazy from collections.abc import Callable, Iterator

from kartka_errors.e2e import E2eLockedError, open_cipher, open_node, read_passphrase
from kartka_errors.render import render, write_todo
from kartka_errors.rtdb import NoSessionError, Rtdb, RtdbError, open_rtdb
from kartka_errors.state import (
    Entry,
    State,
    load_state,
    merge,
    prune,
    resolve,
    save_state,
)

ERRORS_PATH = "kartka-e2e/errors"
#: ``ERRORS_PATH`` relative to the e2e root (the AAD's path).
ERRORS_REL = "errors"
#: Paths deleted per PATCH.
DELETE_CHUNK = 200
EXIT_NO_SESSION = 3
EXIT_LOCKED = 4


def _say(message: str, *, err: bool = False) -> None:
    (sys.stderr if err else sys.stdout).write(f"{message}\n")


def _state_dir() -> Path:
    """``~/.local/state/kartka-errors`` (``$XDG_STATE_HOME`` aware), at call time."""
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "kartka-errors"


def _default_state() -> Path:
    return _state_dir() / "state.json"


def _default_out() -> Path:
    """The report lives beside the state, never inside a repo (no TODO*.md there)."""
    return _state_dir() / "fixme.md"


def _utc_now() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kartka-errors", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    ingest = sub.add_parser("ingest", help="read RTDB, update the fixme report")
    ingest.add_argument("--keep", action="store_true", help="do not delete from RTDB")
    res = sub.add_parser("resolve", help="mark signatures fixed")
    res.add_argument("signatures", nargs="+", help="signature ids (or prefixes)")
    sub.add_parser("render", help="rewrite the fixme report from the state only")
    for p in (ingest, res, sub.choices["render"]):
        p.add_argument(
            "--out", type=Path, default=None, help="default: state dir/fixme.md"
        )
        p.add_argument("--state", type=Path, default=None)
    return parser


def _valid(node: object) -> Entry | None:
    if not isinstance(node, dict):
        return None
    if not all(isinstance(node.get(k), str) for k in ("at", "kind", "error")):
        return None
    entry = {k: v for k, v in node.items() if isinstance(v, str)}
    stack = node.get("stack")
    if isinstance(stack, list):
        entry["stack"] = [str(f) for f in stack]  # type: ignore[assignment]
    return cast("Entry", entry)


def _ingest(
    state: State, rtdb: Rtdb, passphrase: Callable[[], str]
) -> tuple[int, list[str]]:
    """Merge every report; ``(new, paths read)``. No header: nothing yet."""
    cipher = open_cipher(rtdb, passphrase)
    if cipher is None:
        return 0, []
    tree = rtdb.get(ERRORS_PATH)
    new, read = 0, []
    for device, nodes in (tree if isinstance(tree, dict) else {}).items():
        for entry_id, sealed in (nodes if isinstance(nodes, dict) else {}).items():
            read.append(f"{device}/{entry_id}")
            node = open_node(cipher, f"{ERRORS_REL}/{device}/{entry_id}", sealed)
            if (entry := _valid(node)) is not None:
                new += merge(state, str(device), str(entry_id), entry)
    return new, read


def _delete(rtdb: Rtdb, paths: list[str]) -> None:
    for i in range(0, len(paths), DELETE_CHUNK):
        rtdb.patch(ERRORS_PATH, dict.fromkeys(paths[i : i + DELETE_CHUNK]))


@contextmanager
def _locked(state_path: Path) -> Iterator[None]:
    """Hold an exclusive lock beside ``state_path`` (released on close).

    The timer's ingest spends seconds on the network between load and save;
    a ``resolve`` saved in that window would otherwise be overwritten.
    """
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with (state_path.parent / f"{state_path.name}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def main(
    argv: list[str] | None = None,
    *,
    open_rtdb: Callable[[], Rtdb] = open_rtdb,
    now: Callable[[], str] = _utc_now,
    passphrase: Callable[[], str] = read_passphrase,
) -> int:
    """Run one command; see the module docstring."""
    args = _parser().parse_args(argv)
    state_path: Path = args.state or _default_state()
    args.out = args.out or _default_out()
    with _locked(state_path):
        return _run(args, state_path, open_rtdb, now, passphrase)


def _run(
    args: argparse.Namespace,
    state_path: Path,
    open_rtdb: Callable[[], Rtdb],
    now: Callable[[], str],
    passphrase: Callable[[], str],
) -> int:
    state = load_state(state_path)
    stamp = now()
    read: list[str] = []
    summary = ""
    if args.cmd == "ingest":
        try:
            new, read = _ingest(state, open_rtdb(), passphrase)
        except NoSessionError as e:
            _say(f"kartka-errors: {e}", err=True)
            return EXIT_NO_SESSION
        except E2eLockedError as e:
            _say(f"kartka-errors: e2e locked: {e}", err=True)
            return EXIT_LOCKED
        except RtdbError as e:
            _say(f"kartka-errors: {e}", err=True)
            return 1
        prune(state, stamp)
        summary = f"{new} new report(s); "
    elif args.cmd == "resolve":
        for sig in args.signatures:
            if not (hits := resolve(state, sig, stamp)):
                _say(f"kartka-errors: no open signature {sig}", err=True)
                return 1
            summary += f"resolved {', '.join(hits)}; "
    save_state(state_path, state)
    _say(f"{summary}{write_todo(args.out, render(state, stamp))} {args.out}")
    if read and not args.keep:
        try:
            _delete(open_rtdb(), read)
        except RtdbError as e:
            # Kept in the state already; the next run merges them as seen.
            _say(f"kartka-errors: delete failed, retried next run: {e}", err=True)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
