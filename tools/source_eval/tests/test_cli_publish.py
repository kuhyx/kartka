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


def test_firebase_writer_uses_shared_credential(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import crdt_sync

    class Cfg:
        api_key, database_url, email = "key", "https://db.test", "me@example.test"

        def read_password(self) -> str:
            return "pw"

    signed: list[tuple[str, str]] = []

    class Auth:
        def __init__(self, key: str, store: object) -> None:
            assert key == "key"

        def has_session(self) -> bool:
            return bool(signed)

        def sign_in(self, email: str, password: str) -> None:
            signed.append((email, password))

        def id_token(self) -> str:
            return "tok"

    monkeypatch.setattr(
        crdt_sync.FirebaseConfig, "load", classmethod(lambda cls: Cfg())
    )
    monkeypatch.setattr(crdt_sync, "FirebaseTokenProvider", Auth)
    writer = report.firebase_writer()
    assert signed == [("me@example.test", "pw")]
    report.firebase_writer()  # a stored session skips the password sign-in
    assert len(signed) == 1
    assert isinstance(writer, report.FirebaseRtdb)


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
    assert run("report", "--run", "c", "--out", str(tmp_path / "o.json")) == 0
    assert app.select([], installed=True)
    assert len(app.select([], installed=False)) == len(
        catalog.load(app.candidates_path)
    )
    settings = cli._settings(parser.parse_args([*base, "candidates"]))
    assert settings.state_dir == tmp_path / "state"
    assert cli._settings(parser.parse_args(["candidates"])).data_dir.name == "data"
    monkeypatch.setattr(cli, "RequestsTransport", lambda: app.transport)
    monkeypatch.setattr(App, "cmd_candidates", lambda self: (self.out("hi"), 0)[1])
    assert cli.main([*base, "candidates"]) == 0
    assert "hi" in capsys.readouterr().out
    published: list[str] = []

    class W:
        def patch(self, path: str, data: dict[str, object]) -> None:
            published.append(path)

    args = parser.parse_args([*base, "report", "--run", "c", "--publish"])
    assert cli.dispatch(app, args, W) == 0
    assert published == [report.RTDB_PATH]
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
