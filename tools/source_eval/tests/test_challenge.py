# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

from hypothesis import given
from hypothesis import strategies as st
import pytest

from source_eval.challenge import KINDS, classify_http, classify_message
from tests.fakes import resp


@pytest.mark.parametrize(
    ("status", "body", "headers", "kind"),
    [
        (200, "<html>fine</html>", {}, None),
        (200, "<title>Just a moment...</title>", {}, "cloudflare"),
        (200, "ok", {"cf-mitigated": "challenge"}, "cloudflare"),
        (403, "<script src='/cdn-cgi/challenge-platform/h/b'>", {}, "cloudflare"),
        (503, "window._cf_chl_opt={}", {}, "cloudflare"),
        (403, "<div class='g-recaptcha'></div>", {}, "captcha"),
        (403, "<div class='cf-turnstile'></div>", {}, "captcha"),
        (403, "Forbidden", {}, "403"),
        (429, "Too many", {}, "429"),
        (404, "missing", {}, None),
        (
            200,
            "<script src='/cdn-cgi/challenge-platform/scripts/jsd/main.js'>",
            {},
            None,
        ),
    ],
)
def test_classify_http(
    status: int, body: str, headers: dict[str, str], kind: str | None
) -> None:
    assert classify_http(resp(status, body, headers)) == kind


@pytest.mark.parametrize(
    ("msg", "kind"),
    [
        ("Solve captcha in WebView and retry", "captcha"),
        ("Failed to bypass Cloudflare", "cloudflare"),
        ("HTTP error 429", "429"),
        ("HTTP error 403", "403"),
        ("CEF is disabled", "webview"),
        ("WebView not available", "webview"),
        ("HTTP error 404", None),
        ("timeout after 4030ms", None),
    ],
)
def test_classify_message(msg: str, kind: str | None) -> None:
    assert classify_message(msg) == kind


@given(st.text())
def test_classifiers_return_known_kinds(text: str) -> None:
    assert classify_message(text) in (*KINDS, None)
    assert classify_http(resp(403, text)) in KINDS
