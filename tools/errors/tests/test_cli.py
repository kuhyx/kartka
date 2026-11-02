# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
lazy from pathlib import Path

lazy import pytest

from kartka_errors.cli import ERRORS_PATH, main
from kartka_errors.rtdb import NoSessionError, RtdbError


class FakeRtdb:
    def __init__(self, tree: dict[str, object] | None) -> None:
        self.tree = tree
        self.patches: list[tuple[str, dict[str, object]]] = []

    def get(self, path: str) -> object:
        assert path == ERRORS_PATH
        return self.tree

    def patch(self, path: str, data: dict[str, object]) -> None:
        self.patches.append((path, data))


ENTRY = {
    "at": "2026-10-29T10:00:00.000Z",
    "kind": "ui.snackbar",
    "error": "FormatException: repo URL must be http(s): atsumaru",
    "stack": ["#0 f (package:kartka/plugins/runtime/plugin_manager.dart:87:7)"],
    "route": "/more/plugins",
}


def run(tmp_path: Path, rtdb: FakeRtdb | None, *args: str) -> tuple[int, Path]:
    out = tmp_path / "fixme.md"

    def factory() -> FakeRtdb:
        if rtdb is None:
            raise NoSessionError("seed one with: tool.seed_session")
        return rtdb

    code = main(
        [*args, "--out", str(out), "--state", str(tmp_path / "state.json")],
        open_rtdb=factory,
        now=lambda: "2026-10-29T12:00:00Z",
    )
    return code, out


def test_ingest_writes_the_todo_and_deletes_what_it_read(tmp_path: Path) -> None:
    db = FakeRtdb({"dev-a": {"id1": ENTRY, "bad": "not a map"}})
    code, out = run(tmp_path, db, "ingest")
    assert code == 0
    assert "repo URL must be http(s): atsumaru" in out.read_text()
    assert db.patches == [(ERRORS_PATH, {"dev-a/id1": None, "dev-a/bad": None})]
    state = json.loads((tmp_path / "state.json").read_text())
    assert state["seen"] == {"dev-a/id1": ENTRY["at"]}


def test_keep_leaves_rtdb_alone_and_a_rerun_counts_nothing_twice(
    tmp_path: Path,
) -> None:
    db = FakeRtdb({"dev-a": {"id1": ENTRY}})
    assert run(tmp_path, db, "ingest", "--keep")[0] == 0
    assert run(tmp_path, db, "ingest", "--keep")[0] == 0
    assert db.patches == []
    assert "count: 1" in (tmp_path / "fixme.md").read_text()


def test_deletes_in_chunks(tmp_path: Path) -> None:
    many = {
        f"id{i}": {**ENTRY, "at": f"2026-10-29T10:00:{i % 60:02d}.000Z"}
        for i in range(450)
    }
    db = FakeRtdb({"d": many})
    assert run(tmp_path, db, "ingest")[0] == 0
    assert [len(p[1]) for p in db.patches] == [200, 200, 50]


def test_empty_rtdb_and_nothing_open_removes_the_file(tmp_path: Path) -> None:
    (tmp_path / "fixme.md").write_text("stale")
    code, out = run(tmp_path, FakeRtdb(None), "ingest")
    assert code == 0
    assert not out.exists()


def test_resolve_closes_a_signature_and_rerenders(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    run(tmp_path, FakeRtdb({"d": {"1": ENTRY}}), "ingest")
    text = (tmp_path / "fixme.md").read_text()
    sig = text.split("signature: `")[1].split("`")[0]
    assert run(tmp_path, None, "resolve", sig)[0] == 0
    assert not (tmp_path / "fixme.md").exists()
    assert run(tmp_path, None, "resolve", "nope")[0] == 1
    assert "no open signature" in capsys.readouterr().err


def test_render_needs_no_rtdb(tmp_path: Path) -> None:
    run(tmp_path, FakeRtdb({"d": {"1": ENTRY}}), "ingest", "--keep")
    (tmp_path / "fixme.md").unlink()
    assert run(tmp_path, None, "render")[0] == 0
    assert (tmp_path / "fixme.md").exists()


def test_no_session_names_the_seed_command(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert run(tmp_path, None, "ingest")[0] == 3
    assert "seed_session" in capsys.readouterr().err


def test_rtdb_failure_keeps_the_state(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    class Broken(FakeRtdb):
        def get(self, path: str) -> object:
            raise RtdbError("RTDB GET kartka/errors: HTTP 401")

    assert run(tmp_path, Broken(None), "ingest")[0] == 1
    assert "HTTP 401" in capsys.readouterr().err
    assert not (tmp_path / "state.json").exists()


def test_a_failed_delete_is_reported_and_the_state_kept(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    class NoDelete(FakeRtdb):
        def patch(self, path: str, data: dict[str, object]) -> None:
            raise RtdbError("RTDB PATCH kartka/errors: HTTP 500")

    assert run(tmp_path, NoDelete({"d": {"1": ENTRY}}), "ingest")[0] == 1
    assert "retried next run" in capsys.readouterr().err
    assert (tmp_path / "fixme.md").exists()
    db = FakeRtdb({"d": {"1": ENTRY}})
    assert run(tmp_path, db, "ingest")[0] == 0
    assert "count: 1" in (tmp_path / "fixme.md").read_text()
    assert db.patches


def test_non_map_devices_and_entries_without_a_stack(tmp_path: Path) -> None:
    bare = {k: v for k, v in ENTRY.items() if k != "stack"}
    db = FakeRtdb({"d": {"1": bare, "2": {"at": 1}}, "junk": "x"})
    assert run(tmp_path, db, "ingest")[0] == 0
    assert db.patches == [(ERRORS_PATH, {"d/1": None, "d/2": None})]


def test_defaults_follow_xdg_and_utc(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    from kartka_errors import cli

    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    assert cli._default_state() == tmp_path / "kartka-errors" / "state.json"
    monkeypatch.delenv("XDG_STATE_HOME")
    assert cli._default_state().parts[-3:] == ("state", "kartka-errors", "state.json")
    assert cli._utc_now().endswith("Z")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    assert cli.main(["render"], open_rtdb=lambda: FakeRtdb(None)) == 0


def test_default_out_is_outside_the_repo(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No --out: the report lands in ~/.local/state/kartka-errors/fixme.md."""
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_STATE_HOME", raising=False)
    monkeypatch.chdir(tmp_path)
    code = main(
        ["ingest", "--state", str(tmp_path / "state.json")],
        open_rtdb=lambda: FakeRtdb({"phone": {"e1": ENTRY}}),  # type: ignore[arg-type,return-value]
        now=lambda: "2026-10-29T12:00:00Z",
    )
    expected = home / ".local" / "state" / "kartka-errors" / "fixme.md"
    assert code == 0
    assert "count: 1" in expected.read_text()
    assert not (tmp_path / "fixme.md").exists()
