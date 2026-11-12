# Copyright (c) 2026 Krzysztof Rudnicki
"""The evaluator reads the active scoring profile from RTDB and publishes with it."""

from __future__ import annotations

import dataclasses
import json
from typing import TYPE_CHECKING, Any

from crdt_sync._fbkeys import encode_key
import pytest

from source_eval import cli, report
from source_eval.e2e import HEADER
from source_eval.profile import (
    DEFAULT,
    SETTING_KEY,
    SETTING_NODE,
    SETTING_REL,
    Cuts,
    Profile,
)
from source_eval.state import Manifest
from source_eval.synced_profile import load_profile
from tests.app_helpers import make_app
from tests.e2e_support import HEADER_TEXT, seal
from tests.fakes import FakeTransport, resp

if TYPE_CHECKING:
    from pathlib import Path

CUSTOM = dataclasses.replace(DEFAULT, keep_score=0.5, cuts=Cuts(coverage=True))


HLC = "2026-11-12T10:00:00.000Z-0000-dev-a"


def node_for(profile: dict[str, Any] | str) -> dict[str, object]:
    """The settings node the app writes (``value`` a JSON string), sealed."""
    value = profile if isinstance(profile, str) else json.dumps(profile)
    return seal(
        SETTING_REL, {"key": SETTING_KEY, "value": value, "hlc": HLC}, newest=HLC
    )


class Reader:
    """An RTDB reader answering the e2e header and one node."""

    def __init__(self, answer: object, header: object = HEADER_TEXT) -> None:
        self.answer = answer
        self.header = header
        self.paths: list[str] = []

    def get(self, path: str) -> object:
        self.paths.append(path)
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.header if path == HEADER else self.answer

    def patch(self, path: str, data: dict[str, object]) -> None:
        pytest.fail("the profile read must not publish")


def test_node_is_the_settings_namespace_of_the_escaped_key() -> None:
    assert f"kartka-e2e/settings/{encode_key(SETTING_KEY)}" == SETTING_NODE
    assert SETTING_NODE.endswith(SETTING_REL)


def test_firebase_rtdb_get() -> None:
    t = FakeTransport()
    t.add("https://db.test/node.json?auth=tok", resp(200, '{"a": 1}'))
    t.add("https://db.test/none.json?auth=tok", resp(200, "null"))
    t.add("https://db.test/bad", resp(401, "Permission denied"))
    rtdb = report.FirebaseRtdb("https://db.test/", lambda: "tok", t)
    assert rtdb.get("node") == {"a": 1}
    assert t.sent[0].method == "GET"
    assert rtdb.get("none") is None
    with pytest.raises(RuntimeError, match="HTTP 401"):
        rtdb.get("bad")


def test_load_profile_reads_the_synced_setting() -> None:
    reader = Reader(node_for(CUSTOM.to_json()))
    assert load_profile(lambda: reader) == (CUSTOM, None)
    assert reader.paths == [HEADER, HEADER, SETTING_NODE]  # unlock re-reads it


@pytest.mark.parametrize(
    "answer",
    [None, seal(SETTING_REL, {"key": SETTING_KEY, "hlc": HLC}, newest=HLC)],
    ids=["absent", "removed"],
)
def test_no_custom_profile_means_default_without_a_warning(answer: object) -> None:
    assert load_profile(lambda: Reader(answer)) == (DEFAULT, None)


def test_no_e2e_header_means_nothing_synced_yet() -> None:
    reader = Reader(node_for(CUSTOM.to_json()), header=None)
    assert load_profile(lambda: reader) == (DEFAULT, None)
    assert reader.paths == [HEADER]


@pytest.mark.parametrize("secret", ["", "wrong"])
def test_a_locked_profile_falls_back_with_a_warning(
    password_file: Path, secret: str
) -> None:
    password_file.write_text(secret, encoding="utf-8")
    profile, warning = load_profile(lambda: Reader(node_for(CUSTOM.to_json())))
    assert profile == DEFAULT
    assert warning is not None
    assert "locked" in warning


@pytest.mark.parametrize(
    "answer",
    [
        node_for("not json"),
        node_for({"keepScore": 7}),
        node_for("[1]"),
        seal(SETTING_REL, {"key": SETTING_KEY, "value": 3, "hlc": HLC}),
        ["not", "a", "node"],
        {"key": SETTING_KEY, "value": "{}", "hlc": HLC},
        seal("settings/other", {"key": SETTING_KEY, "value": "{}"}),
        RuntimeError("HTTP 401"),
        OSError("offline"),
    ],
    ids=[
        "bad-json",
        "invalid",
        "not-object",
        "value-type",
        "node-type",
        "plaintext",
        "moved",
        "http",
        "os",
    ],
)
def test_unreadable_or_invalid_profile_falls_back_with_a_warning(
    answer: object,
) -> None:
    profile, warning = load_profile(lambda: Reader(answer))
    assert profile == DEFAULT
    assert warning is not None
    assert "DEFAULT" in warning


def test_a_failed_sign_in_falls_back_with_a_warning() -> None:
    def no_session() -> Reader:
        msg = "no credential"
        raise OSError(msg)

    profile, warning = load_profile(no_session)
    assert profile == DEFAULT
    assert warning is not None
    assert "no credential" in warning


def test_build_meta_records_the_profile() -> None:
    meta = report.build_meta("r", "t", 1, [], [], CUSTOM)
    assert meta["profile"] == {"name": "custom", **CUSTOM.to_json()}
    default_meta = report.build_meta("r", "t", 1, [], [])
    assert default_meta["profile"] == {"name": "default", **DEFAULT.to_json()}


def run_report(tmp_path: Path, profile: Profile) -> tuple[dict[str, Any], list[str]]:
    app, _, _, lines = make_app(tmp_path)
    app.cmd_candidates()
    app.cmd_reference(None, 3)
    app.cmd_init_run("c", 2, Manifest([], 1, 1, 1))
    app.cmd_run("c", app.select(["mangadex"], installed=False), None, 1)
    out = tmp_path / "o.json"
    assert app.cmd_report("c", out, None, profile) == 0
    return json.loads(out.read_text()), lines


def test_cmd_report_scores_with_the_profile_and_keeps_the_default_score(
    tmp_path: Path,
) -> None:
    only_up = dataclasses.replace(
        DEFAULT,
        weights=dataclasses.replace(
            DEFAULT.weights,
            complete_coverage=0,
            image_quality=0,
            speed=0,
        ),
    )
    data, lines = run_report(tmp_path, only_up)
    record = data["sources"][0]
    assert record["score"] != record["defaultScore"]
    assert data["meta"]["profile"]["name"] == "custom"
    assert any("profile: custom" in line for line in lines)


def test_cli_report_reads_the_profile_unless_default_is_forced(
    tmp_path: Path,
) -> None:
    app, _, _, lines = make_app(tmp_path)
    base = ["--state-dir", str(tmp_path / "state"), "--data-dir", str(tmp_path)]
    parser = cli._parser()
    app.cmd_candidates()
    app.cmd_reference(None, 3)
    app.cmd_init_run("c", 2, Manifest([], 1, 1, 1))
    reader = Reader(node_for(CUSTOM.to_json()))
    out = str(tmp_path / "o.json")

    def run(*extra: str) -> int:
        args = parser.parse_args([*base, "report", "--run", "c", "--out", out, *extra])
        return cli.dispatch(app, args, lambda: reader)

    assert run("--weights", "default") == 0
    assert reader.paths == []
    assert (
        json.loads((tmp_path / "o.json").read_text())["meta"]["profile"]["name"]
        == "default"
    )
    assert run() == 0
    assert reader.paths == [HEADER, HEADER, SETTING_NODE]  # unlock re-reads it
    assert (
        json.loads((tmp_path / "o.json").read_text())["meta"]["profile"]["name"]
        == "custom"
    )
    reader.answer = node_for("garbage")
    assert run() == 0
    assert any(line.startswith("warning:") for line in lines)
