# Copyright (c) 2026 Krzysztof Rudnicki
"""Assemble the ranked report and (optionally) publish it to RTDB."""

from __future__ import annotations

import datetime as dt
import json
from typing import TYPE_CHECKING, Protocol, cast
lazy from collections.abc import Callable

import crdt_sync

from source_eval.http import Request, RequestsTransport, Transport
from source_eval.metrics import metrics
from source_eval.score import Record, rank
from source_eval.state import sha1
from source_eval.uptime import HOSTS_BLOCKED

if TYPE_CHECKING:
    from source_eval.models import Candidate
    from source_eval.state import Manifest, RunDir
    from source_eval.uptime import UptimeLog

RTDB_PATH = "kartka/source_health"
#: The run meta: a separate node, so ``source_health`` stays ``{sha1(id): record}``.
META_PATH = "kartka/source_health_meta"
APP_NAME = "kartka-source-eval"
_ONLY_KEIYOUSHI = {"native": False, "mangayomiJs": False, "keiyoushi": True}


def build_meta(
    run_id: str,
    generated_at: str,
    candidates: int,
    ranked: list[Record],
    skipped: list[dict[str, object]],
) -> dict[str, object]:
    """Run meta: sizes, verdict counts and what the candidate merge dropped.

    ``tested`` is the number of ranked records (sources the run touched).
    """
    verdicts = {"keep": 0, "cut": 0, "pending": 0}
    for record in ranked:
        verdicts[str(record["verdict"])] += 1
    return {
        "runId": run_id,
        "generatedAt": generated_at,
        "candidates": candidates,
        "tested": len(ranked),
        "verdicts": verdicts,
        "skipped": skipped,
    }


def build_report(  # noqa: PLR0913 -- one argument per input the report joins
    cands: dict[str, Candidate],
    run: RunDir,
    manifest: Manifest,
    log: UptimeLog,
    now: float,
    *,
    skipped: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    """Ranked §5 records for every source the run touched, summary and meta."""
    records: list[Record] = []
    found: dict[str, set[str]] = {}
    for source_id in run.evaluated_ids():
        cand = cands.get(source_id)
        if cand is None:
            continue
        state = run.source(source_id)
        records.append(metrics(cand, state, manifest, log.window(cand.id, now), now))
        found[source_id] = set(state.found())
    ranked = rank(records, found)
    blocked_here = []
    for record in ranked:
        last = log.last(str(record["id"]))
        if last is not None and last.kind == HOSTS_BLOCKED:
            blocked_here.append(record["id"])
    only = [r for r in ranked if r["availability"] == _ONLY_KEIYOUSHI]
    generated = dt.datetime.fromtimestamp(now, dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "generatedAt": generated,
        "runId": run.run_id,
        "referenceSize": len(manifest.sample),
        "sources": ranked,
        "summary": {
            "hostsBlockedHere": blocked_here,
            "keepOnlyViaKeiyoushi": [r["id"] for r in only if r["verdict"] == "keep"],
            "notCutOnlyViaKeiyoushi": [
                {"id": r["id"], "name": r["name"], "verdict": r["verdict"]}
                for r in only
                if r["verdict"] != "cut"
            ],
        },
        "meta": build_meta(run.run_id, generated, len(cands), ranked, skipped or []),
    }


class RtdbWriter(Protocol):
    """Anything that can PATCH a JSON object into RTDB."""

    def patch(self, path: str, data: dict[str, object]) -> None:
        """Merge ``data`` into the node at ``path``."""
        ...


class FirebaseRtdb:
    """RTDB REST writer: stores real JSON objects (not string leaves)."""

    def __init__(
        self, database_url: str, id_token: Callable[[], str], transport: Transport
    ) -> None:
        """Write to ``database_url`` with tokens from ``id_token``."""
        self._url = database_url.rstrip("/")
        self._id_token = id_token
        self._transport = transport

    def patch(self, path: str, data: dict[str, object]) -> None:
        """PATCH ``data`` under ``path``; raises on any non-2xx."""
        url = f"{self._url}/{path}.json?auth={self._id_token()}"
        body = json.dumps(data).encode()
        response = self._transport.send(
            Request("PATCH", url, {"Content-Type": "application/json"}, body)
        )
        if not 200 <= response.status < 300:  # noqa: PLR2004
            msg = f"RTDB PATCH {path}: HTTP {response.status} {response.text()[:200]}"
            raise RuntimeError(msg)


def firebase_writer() -> FirebaseRtdb:
    """Writer signed in with the shared ``~/.config/crdt-sync/`` credential."""
    config = crdt_sync.FirebaseConfig.load()
    store = crdt_sync.credential_store_for(APP_NAME)
    auth = crdt_sync.FirebaseTokenProvider(config.api_key, store)
    if not auth.has_session():
        auth.sign_in(config.email, config.read_password())
    return FirebaseRtdb(config.database_url, auth.id_token, RequestsTransport())


def publish(report: dict[str, object], writer: RtdbWriter) -> int:
    """Write every record to ``/kartka/source_health/<sha1(id)>``, then the meta.

    Returns the record count.
    """
    records = cast("list[Record]", report["sources"])
    writer.patch(RTDB_PATH, {sha1(str(r["id"])): r for r in records})
    writer.patch(META_PATH, cast("dict[str, object]", report["meta"]))
    return len(records)
