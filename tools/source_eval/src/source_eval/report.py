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
from source_eval.profile import DEFAULT, SETTING_NODE, Profile, parse_profile
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
#: What to run (once, in a browser) when the evaluator has no session.
SEED_HINT = (
    "no kartka-source-eval sign-in session; seed one with: cd ~/src/utils/"
    "crdt-sync && python3 -m tool.seed_session --app kartka-source-eval"
    " (full command: SEED_CMD in tools/agent/lib.sh)"
)
_ONLY_KEIYOUSHI = {"native": False, "mangayomiJs": False, "keiyoushi": True}


def build_meta(  # noqa: PLR0913, PLR0917 -- one argument per meta input
    run_id: str,
    generated_at: str,
    candidates: int,
    ranked: list[Record],
    skipped: list[dict[str, object]],
    profile: Profile = DEFAULT,
) -> dict[str, object]:
    """Run meta: sizes, verdict counts, what the merge dropped, the profile.

    ``tested`` is the number of ranked records (sources the run touched);
    ``profile`` is the scoring profile the run was judged with.
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
        "profile": {"name": profile.name, **profile.to_json()},
    }


def build_report(  # noqa: PLR0913 -- one argument per input the report joins
    cands: dict[str, Candidate],
    run: RunDir,
    manifest: Manifest,
    log: UptimeLog,
    now: float,
    *,
    skipped: list[dict[str, object]] | None = None,
    profile: Profile = DEFAULT,
) -> dict[str, object]:
    """Ranked §5 records for every source the run touched, summary and meta.

    Scores, ranks and verdicts follow ``profile``; every record also carries
    its ``defaultScore`` (DEFAULT profile).
    """
    records: list[Record] = []
    found: dict[str, set[str]] = {}
    for source_id in run.evaluated_ids():
        cand = cands.get(source_id)
        if cand is None:
            continue
        state = run.source(source_id)
        records.append(metrics(cand, state, manifest, log.window(cand.id, now), now))
        found[source_id] = set(state.found())
    ranked = rank(records, found, profile)
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
        "meta": build_meta(
            run.run_id, generated, len(cands), ranked, skipped or [], profile
        ),
    }


class RtdbWriter(Protocol):
    """Anything that can PATCH a JSON object into RTDB."""

    def patch(self, path: str, data: dict[str, object]) -> None:
        """Merge ``data`` into the node at ``path``."""
        ...


class RtdbReader(Protocol):
    """Anything that can GET a JSON node from RTDB."""

    def get(self, path: str) -> object:
        """The decoded JSON at ``path`` (``None`` when the node is absent)."""
        ...


class Rtdb(RtdbReader, RtdbWriter, Protocol):
    """Read and write access to RTDB."""


class FirebaseRtdb:
    """RTDB REST client: stores real JSON objects (not string leaves)."""

    def __init__(
        self, database_url: str, id_token: Callable[[], str], transport: Transport
    ) -> None:
        """Write to ``database_url`` with tokens from ``id_token``."""
        self._url = database_url.rstrip("/")
        self._id_token = id_token
        self._transport = transport

    def get(self, path: str) -> object:
        """GET the JSON at ``path``; raises on any non-2xx."""
        url = f"{self._url}/{path}.json?auth={self._id_token()}"
        response = self._transport.send(Request("GET", url, {}, None))
        if not 200 <= response.status < 300:  # noqa: PLR2004
            msg = f"RTDB GET {path}: HTTP {response.status} {response.text()[:200]}"
            raise RuntimeError(msg)
        return response.json()

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


class NoSessionError(RuntimeError):
    """The evaluator has no seeded sign-in session."""


def firebase_writer() -> FirebaseRtdb:
    """RTDB client on the evaluator's seeded Google session.

    The sync account is Google-only, so there is no password sign-in: the
    session is ``~/.config/kartka-source-eval/firebase_auth.json``, written once
    by crdt-sync's ``tool.seed_session --app kartka-source-eval`` and refreshed
    from then on. Raises :class:`NoSessionError` naming that command when
    it is missing.
    """
    config = crdt_sync.FirebaseConfig.load()
    store = crdt_sync.credential_store_for(APP_NAME)
    auth = crdt_sync.FirebaseTokenProvider(config.api_key, store)
    if not auth.has_session():
        raise NoSessionError(SEED_HINT)
    return FirebaseRtdb(config.database_url, auth.id_token, RequestsTransport())


def load_profile(open_reader: Callable[[], RtdbReader]) -> tuple[Profile, str | None]:
    """The active scoring profile (the app's synced setting) and a warning.

    Read-only; ``open_reader`` is called here so a failed sign-in is covered.
    No custom profile (node absent or removed) is DEFAULT with no warning; an
    unreadable or invalid one is DEFAULT plus a warning saying why.
    """
    try:
        node = open_reader().get(SETTING_NODE)
    except Exception as error:  # noqa: BLE001 -- any failure falls back
        return DEFAULT, f"profile unreadable ({error}); scoring with DEFAULT"
    if node is None:
        return DEFAULT, None
    value = node.get("value") if isinstance(node, dict) else None
    if value is None and isinstance(node, dict):
        return DEFAULT, None  # a removal node: only {key, hlc}
    try:
        parsed = parse_profile(json.loads(value)) if isinstance(value, str) else None
    except ValueError:
        parsed = None
    if parsed is None:
        return DEFAULT, "profile invalid; scoring with DEFAULT"
    return parsed, None


def publish(report: dict[str, object], writer: RtdbWriter) -> int:
    """Write every record to ``/kartka/source_health/<sha1(id)>``, then the meta.

    Returns the record count.
    """
    records = cast("list[Record]", report["sources"])
    writer.patch(RTDB_PATH, {sha1(str(r["id"])): r for r in records})
    writer.patch(META_PATH, cast("dict[str, object]", report["meta"]))
    return len(records)
