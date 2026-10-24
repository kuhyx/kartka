# Copyright (c) 2026 Krzysztof Rudnicki
"""Assemble the ranked report and (optionally) publish it to RTDB."""

from __future__ import annotations

from collections.abc import Callable
import datetime as dt
import json
from typing import TYPE_CHECKING, Protocol, cast

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
APP_NAME = "kartka-source-eval"
_ONLY_KEIYOUSHI = {"native": False, "mangayomiJs": False, "keiyoushi": True}


def build_report(  # noqa: PLR0913 -- inputs of one pure aggregation
    cands: dict[str, Candidate],
    run: RunDir,
    run_id: str,
    manifest: Manifest,
    log: UptimeLog,
    now: float,
) -> dict[str, object]:
    """Ranked §5 records for every source the run touched, plus a summary."""
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
    return {
        "generatedAt": dt.datetime.fromtimestamp(now, dt.UTC).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "runId": run_id,
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


def firebase_writer() -> FirebaseRtdb:  # pragma: no cover -- live credentials only
    """Writer signed in with the shared ``~/.config/crdt-sync/`` credential."""
    from crdt_sync import FirebaseConfig, FirebaseTokenProvider, credential_store_for

    config = FirebaseConfig.load()
    auth = FirebaseTokenProvider(config.api_key, credential_store_for(APP_NAME))
    if not auth.has_session():
        auth.sign_in(config.email, config.read_password())
    return FirebaseRtdb(config.database_url, auth.id_token, RequestsTransport())


def publish(report: dict[str, object], writer: RtdbWriter) -> int:
    """Write every record to ``/kartka/source_health/<sha1(id)>``; returns count."""
    records = cast("list[Record]", report["sources"])
    writer.patch(RTDB_PATH, {sha1(str(r["id"])): r for r in records})
    return len(records)
