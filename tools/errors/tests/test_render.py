# Copyright (c) 2026 Krzysztof Rudnicki
from pathlib import Path

from kartka_errors.render import MARKER, MAX_SECTIONS, render, write_todo
from kartka_errors.state import State, load_state, merge


def filled(n: int = 1) -> State:
    state = load_state(Path("/nonexistent"))
    for i in range(n):
        merge(
            state,
            "dev-a",
            f"id{i}",
            {
                "at": f"2026-10-29T10:{i % 60:02d}:00.000Z",
                "kind": "reader.open",
                "error": f"SuwayomiException{i}: CEF is disabled",
                "stack": [
                    "#0 f (package:kartka/sources/s.dart:1:2)",
                    "#1 g (dart:async)",
                ],
                "route": "/read/:sourceId/:mangaUrl/:chapterUrl",
                "sourceId": "suwayomi",
                "chapterUrl": "/chapter/1",
            },
        )
    return state


def test_starts_with_the_marker_then_a_prompt_then_sections() -> None:
    text = render(filled(), "2026-10-29T12:00:00Z")
    assert text is not None
    lines = text.splitlines()
    assert lines[0] == MARKER
    assert "REMOVE ME AFTER FINISH" in lines[0]
    assert "write a failing test first" in text
    assert "tools/errors/run.sh resolve" in text
    assert "SuwayomiException0: CEF is disabled" in text
    assert "/read/:sourceId/:mangaUrl/:chapterUrl" in text
    assert "#0 f (package:kartka/sources/s.dart:1:2)" in text
    assert "count: 1" in text
    assert "/chapter/1" in text


def test_nothing_open_renders_nothing() -> None:
    assert render(load_state(Path("/nonexistent")), "now") is None


def test_caps_the_sections_and_says_how_many_more() -> None:
    text = render(filled(MAX_SECTIONS + 3), "now")
    assert text is not None
    assert text.count("\n## ") == MAX_SECTIONS + 1  # + the prompt heading
    assert "3 more" in text


def test_write_todo_creates_and_deletes(tmp_path: Path) -> None:
    out = tmp_path / "TODO-fixme.md"
    assert write_todo(out, "x\n") == "wrote"
    assert out.read_text() == "x\n"
    assert write_todo(out, None) == "removed"
    assert not out.exists()
    assert write_todo(out, None) == "nothing open"


def test_a_bare_entry_renders_without_optional_lines() -> None:
    state = load_state(Path("/nonexistent"))
    merge(state, "d", "1", {"at": "2026-10-29T10:00:00.000Z", "kind": "k", "error": ""})
    text = render(state, "now")
    assert text is not None
    assert "routes:" not in text
    assert "Stack" not in text
    assert "## k: ?" in text


def test_a_message_naming_its_type_is_not_prefixed_twice() -> None:
    state = load_state(Path("/nonexistent"))
    merge(
        state,
        "d",
        "1",
        {"at": "2026-10-29T10:00:00.000Z", "kind": "k", "error": "FormatException: x"},
    )
    text = render(state, "now")
    assert text is not None
    assert "## FormatException: x\n" in text
