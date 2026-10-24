# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
lazy from pathlib import Path

import pytest

from source_eval import report
from source_eval.app import MORE_WORK
from source_eval.candidates import catalog
from source_eval.http import TransportError
from source_eval.models import Candidate
from source_eval.polite import Observation
from source_eval.state import Manifest
from source_eval.uptime import (
    HOSTS_BLOCKED,
    UptimeLog,
    failed,
    locally_blocked,
    resolve,
    summarize,
)
from tests.app_helpers import SUWA, make_app
from tests.fakes import resp


def test_end_to_end_commands(tmp_path: Path) -> None:
    app, _, clock, lines = make_app(tmp_path)
    assert app.cmd_candidates() == 0
    cands = catalog.load(app.candidates_path)
    assert cands[-1].id == "plugin:legacy-x"
    assert app.cmd_reference(0, 3) == MORE_WORK
    assert app.cmd_reference(None, 3) == 0
    assert app.cmd_init_run("t", 2, Manifest([], 2, 1, 2)) == 0
    assert (
        app.cmd_init_run("t", 9, Manifest([], 9, 9, 9)) == 0
    )  # idempotent: sample stays fixed
    assert app.cmd_enrich("t", 0) in {0, MORE_WORK}
    assert app.cmd_enrich("t", None) == 0
    chosen = [
        c
        for c in cands
        if c.id in {"mangadex", "suwayomi:4709139914729853090"} or c.origin == "plugin"
    ]
    assert app.cmd_probe(chosen, 4) == 0
    assert app.cmd_run("t", chosen, 0, 1) == MORE_WORK
    assert app.cmd_run("t", chosen, None, 2) == 0
    clock.advance(60)
    published: list[dict[str, object]] = []

    class Writer:
        def patch(self, path: str, data: dict[str, object]) -> None:
            assert path == report.RTDB_PATH
            published.append(data)

    out = tmp_path / "out" / "r.json"
    assert app.cmd_report("t", out, Writer()) == 0
    data = json.loads(out.read_text())
    by_id = {r["id"]: r for r in data["sources"]}
    assert by_id["mangadex"]["coverage"]["found"] is not None
    assert by_id["suwayomi:4709139914729853090"]["blocking"]["kinds"] == ["cloudflare"]
    assert by_id["plugin:legacy-x"]["verdict"] == "pending"
    assert "cloudflare" in str(by_id)
    assert len(published[0]) == len(data["sources"])
    assert any("published" in line for line in lines)
    # A source the candidate list no longer has is skipped; a hosts-blocked
    # last probe is surfaced in the summary.
    (app.s.state_dir / "runs" / "t" / "sources" / "ghost.json").write_text(
        json.dumps({"id": "gone:1"})
    )
    app.uptime.append(
        "plugin:legacy-x",
        Observation(clock.now(), "legacy.test", False, 0.0, HOSTS_BLOCKED, None),
    )
    assert app.cmd_report("t", out, None) == 0
    again = json.loads(out.read_text())
    assert again["summary"]["hostsBlockedHere"] == ["plugin:legacy-x"]
    assert "gone:1" not in {r["id"] for r in again["sources"]}
    with pytest.raises(SystemExit, match="init-run"):
        app.cmd_run("nope", chosen, None, 1)


def test_probe_records_failures_and_local_blocks(tmp_path: Path) -> None:
    app, t, clock, _ = make_app(tmp_path)
    dead = Candidate(
        "suwayomi:9", "Dead", "en", "suwayomi", "https://dead.test", pkg="p"
    )
    t.routes.insert(0, (f"{SUWA}/api/graphql", [TransportError("refused")]))
    obs = app.probe_one(dead)
    assert not obs.ok
    t.routes.pop(0)
    t.routes.insert(
        0,
        (
            f"{SUWA}/api/graphql",
            [
                resp(200, {"data": {"source": {"id": "9"}}}),
                resp(200, {"errors": [{"message": "boom"}]}),
            ],
        ),
    )
    assert not app.probe_one(dead).ok
    gone = Candidate("plugin:gone", "Gone", "en", "plugin", "https://unrouted.test")
    assert not app.probe_one(gone).ok
    assert locally_blocked("x", lambda h: ["0.0.0.0", "::"])
    assert not locally_blocked("x", lambda h: [])
    assert not locally_blocked("x", lambda h: ["1.2.3.4"])
    assert failed(clock, "x", lambda h: ["0.0.0.0"]).kind == HOSTS_BLOCKED
    assert resolve("localhost")
    assert resolve("no-such-host.invalid") == []
    log = UptimeLog(tmp_path / "u")
    assert log.last("k") is None
    log.append("k", Observation(clock.now(), "h", False, 0.0, HOSTS_BLOCKED, None))
    assert log.window("k", clock.now()) == []
    assert log.last("k") is not None
    final = [
        Observation(clock.now() - 8 * 86400 + i * 86400, "h", True, 1.0, None, 200)
        for i in range(8)
    ]
    assert summarize(final, clock.now())["status"] == "final"
