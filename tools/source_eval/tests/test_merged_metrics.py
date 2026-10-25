# Copyright (c) 2026 Krzysztof Rudnicki
"""Session-8 record fields: merged coverage, hard filter inputs, install info."""

from __future__ import annotations

from typing import cast
lazy from pathlib import Path

from source_eval.candidates.catalog import MANGAYOMI_INDEX
from source_eval.metrics import complete_titles, install_info, metrics, unreachable
from source_eval.models import Candidate
from source_eval.polite import Observation
from source_eval.state import Manifest, RunDir, SourceState

CAND = Candidate("suwayomi:1", "Fake", "en", "suwayomi", "https://fake.test", "eu.x")


def state_with(tmp_path: Path, chapters: dict[str, dict[str, object]]) -> SourceState:
    state = RunDir(tmp_path, "t").source(CAND.id)
    state.titles = {k: {"status": "found"} for k in chapters}
    state.titles["miss"] = {"status": "missing"}
    state.chapters = {k: v for k, v in chapters.items() if v}
    return state


def test_a_title_counts_with_80_percent_of_the_reference_chapters(
    tmp_path: Path,
) -> None:
    state = state_with(
        tmp_path,
        {
            "full": {"count": 10, "ratio": 1.0},
            "edge": {"count": 8, "ratio": 0.8},
            "short": {"count": 7, "ratio": 0.7},
            "nocount": {"count": 1, "ratio": None},
            "empty": {"count": 0, "ratio": None},
            "failed": {"error": "HTTP 500"},
            "unlisted": {},
        },
    )
    assert complete_titles(state) == 3  # full, edge, nocount


def test_merged_coverage_only_for_a_run_fetching_every_chapter_list(
    tmp_path: Path,
) -> None:
    state = state_with(tmp_path, {"a": {"count": 9, "ratio": 0.9}, "b": {}})
    sample = ["a", "b", "miss", "x"]
    new = metrics(CAND, state, Manifest(sample, 1, 1, 1, all_chapters=True), [], 0.0)
    assert new["coverage"] == {
        "referenceSize": 4,
        "found": 2,
        "ratio": 0.5,
        "complete": 1,
        "completeRatio": 0.25,
    }
    old = metrics(CAND, state, Manifest(sample, 1, 1, 1), [], 0.0)
    assert cast("dict[str, object]", old["coverage"])["completeRatio"] is None
    plugin = Candidate("plugin:legacy-x", "X", "en", "plugin", "https://x.test")
    unmeasured = metrics(plugin, state, Manifest(sample, 1, 1, 1, True), [], 0.0)
    assert cast("dict[str, object]", unmeasured["coverage"])["complete"] is None


def test_hard_rate_counts_only_non_webview_challenges(tmp_path: Path) -> None:
    state = state_with(tmp_path, {})
    for kind in ("webview", "webview", "cloudflare", None):
        state.observe(Observation(0.0, "fake.test", kind is None, 10.0, kind, 200))
    m = metrics(CAND, state, Manifest(["miss"], 1, 1, 1), [], 0.0)
    assert m["blocking"] == {
        "challengeRate": 0.75,
        "kinds": ["cloudflare", "webview"],
        "hardRate": 0.25,
    }


def test_unreachable_unless_only_a_browser_engine_was_missing(
    tmp_path: Path,
) -> None:
    state = state_with(tmp_path, {})
    state.titles = {f"k{i}": {"status": "error", "kind": None} for i in range(5)}
    assert not unreachable(state)  # not aborted
    state.aborted = "unreachable"
    assert unreachable(state)
    for row in state.titles.values():
        row["kind"] = "webview"
    assert not unreachable(state)
    state.aborted = "blocking"
    assert not unreachable(state)


def test_install_info_names_the_package_or_the_plugin() -> None:
    assert install_info(CAND) == {"pkg": "eu.x", "plugin": None}
    js = Candidate("plugin:mangayomi-955190069", "Comick", "en", "plugin", "https://c")
    assert install_info(js) == {
        "pkg": None,
        "plugin": {"repo": MANGAYOMI_INDEX, "id": "mangayomi-955190069"},
    }
    legacy = Candidate("plugin:legacy-batoto", "Bato", "all", "plugin", "https://b")
    assert install_info(legacy) == {"pkg": None, "plugin": None}
