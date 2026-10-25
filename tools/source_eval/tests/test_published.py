# Copyright (c) 2026 Krzysztof Rudnicki
"""``published --run``: weekly.sh's no-op test for a week already published."""

from __future__ import annotations

import json
lazy from pathlib import Path

import pytest

from source_eval import cli, publishing
from source_eval.budget import MORE_WORK
from tests.app_helpers import make_app
from tests.test_publish_batches import _published_run


def _check(state: Path, run_id: str) -> tuple[int, list[str]]:
    lines: list[str] = []
    return publishing.published_cmd(state, run_id, lines.append), lines


def test_published_only_once_the_last_step_is_written(tmp_path: Path) -> None:
    """The marker is the finished publish's ``hard_cut.json``, nothing earlier."""
    app, clock, _ = _published_run(tmp_path)
    state = app.s.state_dir
    assert _check(state, "t") == (MORE_WORK, ["published: t not yet"])

    class SlowWriter:
        def patch(self, path: str, data: dict[str, object]) -> None:
            clock.advance(30.0)

    out = tmp_path / "r.json"
    assert app.cmd_report("t", out, SlowWriter(), budget=50.0) == MORE_WORK
    assert (state / "runs" / "t" / "publish.json").exists()
    assert _check(state, "t")[0] == MORE_WORK  # interrupted mid-publish
    assert app.cmd_report("t", out, SlowWriter(), budget=50.0) == 0
    assert _check(state, "t") == (0, ["published: t yes"])
    assert _check(state, "u")[0] == MORE_WORK  # another week


@pytest.mark.parametrize("content", ["[]", '{"ids": []}'])
def test_a_malformed_marker_is_not_published(tmp_path: Path, content: str) -> None:
    (tmp_path / publishing.HARD_CUT_FILE).write_text(content)
    assert _check(tmp_path, "t")[0] == MORE_WORK


def test_cli_published(tmp_path: Path) -> None:
    app, _, _, lines = make_app(tmp_path)
    parser = cli._parser()

    def run(run_id: str) -> int:
        args = parser.parse_args(["published", "--run", run_id])
        return cli.dispatch(app, args, lambda: pytest.fail("no rtdb"))

    assert run("2026-W43") == MORE_WORK  # no state dir yet
    app.s.state_dir.mkdir(parents=True)
    (app.s.state_dir / publishing.HARD_CUT_FILE).write_text(
        json.dumps({"runId": "2026-W43", "ids": []})
    )
    assert run("2026-W43") == 0
    assert lines[-1] == "published: 2026-W43 yes"
