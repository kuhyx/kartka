# Copyright (c) 2026 Krzysztof Rudnicki
"""The local record of every report ingested, grouped by signature.

It is the source of truth once RTDB entries are deleted: ``seen`` makes a
re-read (``--keep``) count nothing twice, and each signature keeps its
count, first/last seen, devices, routes, sources and one sample entry. A
resolved signature reopens when a report newer than the fix arrives.
"""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import tempfile
from typing import NotRequired, TypedDict, cast

from kartka_errors import slow
from kartka_errors.signature import signature, top_frame


class Entry(TypedDict):
    """A decoded ``DiagnosticEntry`` as the app uploads it."""

    at: str
    kind: str
    error: str
    stack: NotRequired[list[str]]
    route: NotRequired[str]
    sourceId: NotRequired[str]
    mangaUrl: NotRequired[str]
    chapterUrl: NotRequired[str]
    operation: NotRequired[str]
    durationMs: NotRequired[int]
    waitId: NotRequired[str]
    still: NotRequired[bool]
    build: NotRequired[int]
    version: NotRequired[str]


class Wait(TypedDict):
    """One slow wait: ``id`` is ``device/waitId``, ``ms`` its longest report."""

    id: str
    ms: int
    at: str


class BuildSeen(TypedDict):
    """The newest report of one device that named its build."""

    at: str
    build: int
    version: str | None


class SigRecord(TypedDict):
    """Everything known about one signature."""

    id: str
    type: str
    where: str
    count: int
    first: str
    last: str
    kinds: list[str]
    devices: list[str]
    routes: list[str]
    sources: list[str]
    sample: Entry
    resolved: str | None
    reopened: bool
    # The fields the board reads (docs/DOCS-error-reports.md), derived from
    # the ones above on every merge and on load, so an old state gains them.
    app: str
    signature: str
    kind: str
    message: str
    top_frame: str | None
    first_seen: str
    last_seen: str
    build: int | None
    build_min: int | None
    version_name: str | None
    detail: dict[str, object]
    builds: dict[str, BuildSeen]
    #: The last ``slow.MAX_WAITS`` slow waits.
    waits: list[Wait]


class State(TypedDict):
    """The whole state file."""

    version: int
    seen: dict[str, str]
    signatures: dict[str, SigRecord]


def _empty() -> State:
    return {"version": 1, "seen": {}, "signatures": {}}


def load_state(path: Path) -> State:
    """The state at ``path``; empty when missing or unreadable."""
    try:
        data = json.loads(path.read_text())
    except OSError, ValueError:
        return _empty()
    if not isinstance(data, dict) or data.get("version") != 1:
        return _empty()
    state = cast("State", data)
    for rec in state["signatures"].values():
        if "app" not in cast("dict[str, object]", rec):  # pre-board-fields state
            rec["builds"], rec["waits"], rec["detail"] = {}, [], {}
            rec["build"] = rec["build_min"] = rec["version_name"] = None
            _derive(rec)
    return state


def save_state(path: Path, state: State) -> None:
    """Write ``state`` atomically (temp file + rename), mode 0600."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".state-")
    with os.fdopen(fd, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    Path(tmp).replace(path)


def _add(values: list[str], value: object) -> None:
    if isinstance(value, str) and value and value not in values:
        values.append(value)
        values.sort()


def _note_build(rec: SigRecord, device: str, entry: Entry) -> None:
    """Track the newest build seen, and each device's latest one."""
    build = entry.get("build")
    if build is None or isinstance(build, bool):
        return
    version = entry.get("version")
    top = rec["build"]
    if top is None or build > top:
        rec["build"], rec["version_name"] = build, version
    mine = rec["builds"].get(device)
    if mine is None or entry["at"] >= mine["at"]:
        rec["builds"][device] = {"at": entry["at"], "build": build, "version": version}
    rec["build_min"] = min(b["build"] for b in rec["builds"].values())


def _derive(rec: SigRecord) -> None:
    """Fill the board fields that follow from the rest of the record."""
    sample = rec["sample"]
    sig = signature(cast("dict[str, object]", sample))
    rec["app"] = "kartka"
    rec["signature"] = rec["id"]
    rec["kind"] = sample["kind"]
    rec["message"] = sig.message
    rec["top_frame"] = top_frame(sample.get("stack", []))
    rec["first_seen"] = rec["first"]
    rec["last_seen"] = rec["last"]
    if sample["kind"] != slow.KIND:
        rec["detail"] = {"routes": rec["routes"], "sources": rec["sources"]}


def merge(state: State, device: str, entry_id: str, entry: Entry) -> bool:
    """Count ``entry`` under its signature; False when already seen."""
    key = f"{device}/{entry_id}"
    if key in state["seen"]:
        return False
    state["seen"][key] = entry["at"]
    sig = signature(cast("dict[str, object]", entry))
    rec = state["signatures"].get(sig.id)
    if rec is None:
        rec = state["signatures"][sig.id] = {
            "id": sig.id,
            "type": sig.type,
            "where": sig.where,
            "count": 0,
            "first": entry["at"],
            "last": entry["at"],
            "kinds": [],
            "devices": [],
            "routes": [],
            "sources": [],
            "sample": entry,
            "resolved": None,
            "reopened": False,
            "app": "kartka",
            "signature": sig.id,
            "kind": entry["kind"],
            "message": sig.message,
            "top_frame": None,
            "first_seen": entry["at"],
            "last_seen": entry["at"],
            "build": None,
            "build_min": None,
            "version_name": None,
            "detail": {},
            "builds": {},
            "waits": [],
        }
    if entry["kind"] == slow.KIND:
        slow.add_wait(rec, device, entry_id, entry)
    else:
        rec["count"] += 1
    rec["first"] = min(rec["first"], entry["at"])
    if entry["at"] >= rec["last"]:
        rec["last"] = entry["at"]
        rec["sample"] = entry
    _add(rec["kinds"], entry["kind"])
    _add(rec["devices"], device)
    _add(rec["routes"], entry.get("route"))
    _add(rec["sources"], entry.get("sourceId"))
    _note_build(rec, device, entry)
    _derive(rec)
    resolved = rec["resolved"]
    if resolved is not None and entry["at"] > resolved:
        rec["resolved"] = None
        rec["reopened"] = True
    return True


def resolve(state: State, prefix: str, now: str) -> list[str]:
    """Mark open signatures starting with ``prefix`` fixed at ``now``."""
    hits = [r["id"] for r in open_signatures(state) if r["id"].startswith(prefix)]
    for sig_id in hits:
        state["signatures"][sig_id]["resolved"] = now
        state["signatures"][sig_id]["reopened"] = False
    return hits


def open_signatures(state: State) -> list[SigRecord]:
    """Unresolved signatures, most recently seen first."""
    records = [r for r in state["signatures"].values() if r["resolved"] is None]
    return sorted(records, key=lambda r: (r["last"], r["count"]), reverse=True)


def prune(state: State, now: str, *, days: int = 60) -> None:
    """Forget seen ids older than ``days`` (RTDB no longer has them)."""
    cutoff = dt.datetime.fromisoformat(now) - dt.timedelta(days=days)
    stamp = cutoff.strftime("%Y-%m-%dT%H:%M:%S")
    state["seen"] = {k: at for k, at in state["seen"].items() if at >= stamp}
