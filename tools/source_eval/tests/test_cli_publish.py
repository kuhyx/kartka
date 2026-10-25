# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
lazy from pathlib import Path

import pytest

from source_eval import cli, report
from source_eval.app import App
from source_eval.candidates import catalog
from tests.app_helpers import make_app
from tests.fakes import FakeTransport, resp


def test_firebase_rtdb_writer() -> None:
    t = FakeTransport()
    t.add("https://db.test/kartka/source_health.json?auth=tok", resp(200, "{}"))
    t.add("https://db.test/bad", resp(401, "Permission denied"))
    writer = report.FirebaseRtdb("https://db.test/", lambda: "tok", t)
    writer.patch("kartka/source_health", {"a": {"id": "x"}})
    assert t.sent[0].method == "PATCH"
    assert json.loads(t.sent[0].body or b"{}") == {"a": {"id": "x"}}
    with pytest.raises(RuntimeError, match="HTTP 401"):
        writer.patch("bad", {})


def test_firebase_writer_uses_the_seeded_session(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The evaluator signs in only with its seeded Google session.

    The account is Google-only, so there is no password fallback: with no
    session the writer fails and names the seed command.
    """
    import crdt_sync

    class Cfg:
        api_key, database_url = "key", "https://db.test"

    session = [False]
    apps: list[str] = []

    class Auth:
        def __init__(self, key: str, store: object, *, timeout_seconds: float) -> None:
            assert key == "key"
            assert store == "store"
            assert timeout_seconds == report.TOKEN_TIMEOUT

        def has_session(self) -> bool:
            return session[0]

        def id_token(self) -> str:
            return "tok"

    def store_for(app: str) -> str:
        apps.append(app)
        return "store"

    monkeypatch.setattr(
        crdt_sync.FirebaseConfig, "load", classmethod(lambda cls: Cfg())
    )
    monkeypatch.setattr(crdt_sync, "FirebaseTokenProvider", Auth)
    monkeypatch.setattr(crdt_sync, "credential_store_for", store_for)
    with pytest.raises(report.NoSessionError, match="seed_session") as err:
        report.firebase_writer()
    assert "--app kartka-source-eval" in str(err.value)
    session[0] = True
    writer = report.firebase_writer()
    assert isinstance(writer, report.FirebaseRtdb)
    assert writer._id_token() == "tok"  # through the bounded call
    assert apps == ["kartka-source-eval", "kartka-source-eval"]


def test_cli_dispatch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    app, _, _, lines = make_app(tmp_path)
    base = [
        "--state-dir",
        str(tmp_path / "state"),
        "--data-dir",
        str(tmp_path / "data"),
    ]
    parser = cli._parser()

    def run(*argv: str) -> int:
        return cli.dispatch(
            app, parser.parse_args([*base, *argv]), lambda: pytest.fail("no publish")
        )

    assert run("candidates") == 0
    assert run("reference", "--top", "3") == 0
    assert run("init-run", "--run", "c", "--sample", "2") == 0
    assert run("enrich", "--run", "c") == 0
    assert run("probe", "--ids", "mangadex") == 0
    assert run("run", "--run", "c", "--ids", "mangadex", "--workers", "1") == 0
    assert run("ramp", "start", "--run", "d", "--sample", "2") == 0
    assert run("init-run", "--run", "d", "--ramp", "--reprobe") == 0
    assert run("run", "--run", "d", "--inflight", "2", "--budget", "50") == 0
    assert run("probe", "--ids", "mangadex", "--fresh", "60", "--budget", "50") == 0
    assert run("ramp", "finish", "--run", "d") == 0
    assert cli.args_pool(parser.parse_args(["run", "--inflight", "7"])) == 7
    assert cli.args_pool(parser.parse_args(["probe", "--workers", "9"])) == 9
    assert cli.args_pool(parser.parse_args(["candidates"])) == 0
    out = str(tmp_path / "o.json")
    assert run("report", "--run", "c", "--out", out, "--weights", "default") == 0
    assert app.select([], installed=True)
    assert len(app.select([], installed=False)) == len(
        catalog.load(app.candidates_path)
    )
    settings = cli._settings(parser.parse_args([*base, "candidates"]))
    assert settings.state_dir == tmp_path / "state"
    assert cli._settings(parser.parse_args(["candidates"])).data_dir.name == "data"
    pools: list[int] = []

    def transport(pool: int) -> object:
        pools.append(pool)
        return app.transport

    monkeypatch.setattr(cli, "RequestsTransport", transport)
    monkeypatch.setattr(
        App, "cmd_candidates", lambda self, budget: (self.out("hi"), 0)[1]
    )
    assert cli.main([*base, "candidates"]) == 0
    assert "hi" in capsys.readouterr().out
    assert pools == [16]
    published: list[str] = []

    class W:
        def get(self, path: str) -> object:
            return None  # no custom profile has been set

        def patch(self, path: str, data: dict[str, object]) -> None:
            published.append(path)

    args = parser.parse_args([*base, "report", "--run", "c", "--publish"])
    assert cli.dispatch(app, args, W) == 0
    assert published == [report.RTDB_PATH, report.META_PATH]
    assert lines


def test_suwayomi_credentials_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUWAYOMI_USER", "kuhy")
    monkeypatch.setenv("SUWAYOMI_PASSWORD", "pw")
    monkeypatch.delenv("KARTKA_SUWAYOMI_USER", raising=False)
    monkeypatch.delenv("KARTKA_SUWAYOMI_PASS", raising=False)
    settings = cli._settings(cli._parser().parse_args(["candidates"]))
    assert (settings.suwayomi.user, settings.suwayomi.password) == ("kuhy", "pw")
    monkeypatch.setenv("KARTKA_SUWAYOMI_USER", "other")
    assert cli._env("KARTKA_SUWAYOMI_USER", "SUWAYOMI_USER") == "other"
    assert cli._env("NOPE_A", "NOPE_B", default="d") == "d"


def test_every_network_command_defaults_to_a_55_s_batch() -> None:
    parser = cli._parser()
    for argv in (["candidates"], ["reference"], ["enrich"], ["probe"], ["run"]):
        assert parser.parse_args(argv).budget == cli.DEFAULT_BUDGET == 55.0
    assert parser.parse_args(["report"]).budget == 55.0
    assert parser.parse_args(["run", "--budget", "20"]).budget == 20.0
