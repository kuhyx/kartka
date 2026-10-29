# Copyright (c) 2026 Krzysztof Rudnicki
from kartka_errors.signature import error_type, normalise, signature, top_frame


def test_type_comes_from_the_message_prefix() -> None:
    assert error_type("FormatException: repo URL", "ui.snackbar") == "FormatException"
    assert (
        error_type("SuwayomiException: Exception while fetching", "reader.open")
        == "SuwayomiException"
    )
    assert error_type("Bad state: x", "uncaught.async") == "StateError"
    assert error_type("Install failed: HTTP 500", "ui.snackbar") == "ui.snackbar"


def test_normalise_drops_volatile_parts() -> None:
    a = normalise(
        "HTTP 503 at <url> for 3f2504e0-4f89-11d3-9a0c-0305e82c3301 id deadbeef12"
    )
    assert a == "HTTP <n> at <url> for <uuid> id <hex>"
    assert normalise("x https://h.test/a?b=1  and  more") == "x <url> and more"
    assert len(normalise("y" * 500)) == 160


def test_top_frame_is_the_first_app_frame_without_line_numbers() -> None:
    stack = [
        "#0      List.[] (dart:core-patch/growable_array.dart:264:36)",
        "#1  _Messenger.show (package:kartka/app/error_hooks.dart:82:7)",
        "#2  ErrorReporter.report (package:kartka/core/diagnostics/x.dart:3:1)",
        "#3  ReaderSession.open (package:kartka/reader/state/session.dart:152:7)",
    ]
    assert top_frame(stack) == (
        "ReaderSession.open (package:kartka/reader/state/session.dart)"
    )
    assert top_frame(["#0 a (dart:core/x.dart:1:2)"]) is None
    assert top_frame([]) is None


def test_signature_groups_the_same_bug() -> None:
    base = {
        "at": "2026-10-29T12:00:00.000Z",
        "kind": "reader.open",
        "error": "SuwayomiException: fetching (/fetchChapterPages) : CEF is disabled",
        "stack": ["#0 f (package:kartka/sources/suwayomi/c.dart:10:2)"],
    }
    moved = {**base, "stack": ["#4 f (package:kartka/sources/suwayomi/c.dart:99:1)"]}
    other = {**base, "error": "SuwayomiException: other"}
    assert signature(base).id == signature(moved).id
    assert signature(base).id != signature(other).id
    sig = signature(base)
    assert sig.type == "SuwayomiException"
    assert sig.where == "f (package:kartka/sources/suwayomi/c.dart)"
    assert len(sig.id) == 10


def test_without_an_app_frame_the_route_then_kind_places_it() -> None:
    entry = {"at": "x", "kind": "ui.snackbar", "error": "e", "route": "/browse"}
    assert signature(entry).where == "route /browse"
    assert signature({"at": "x", "kind": "k", "error": "e"}).where == "kind k"
