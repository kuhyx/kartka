# Copyright (c) 2026 Krzysztof Rudnicki
"""Recognise anti-bot challenges. Detection only: nothing here solves them.

A challenged request is evidence that the source fights API access. It is
counted as blocking and never retried through a solver.
"""

from __future__ import annotations

import re

lazy from source_eval.http import Response

#: Every kind a blocking record may list. ``webview`` = the extension needs a
#: browser engine (disabled on purpose) to read the site.
KINDS = ("cloudflare", "captcha", "403", "429", "webview")

#: The one kind that is flagged, not cut: a source that merely needs a browser
#: engine is still a source worth reading (decision 2026-10-24, AllManga).
WEBVIEW = "webview"
#: ``flags`` entry (contract §5) raised whenever ``webview`` challenges are seen.
FLAG_BROWSER_ENGINE = "needs-browser-engine"

_CF_MARKERS = (
    "cf-chl",
    "_cf_chl_opt",
    "challenges.cloudflare.com",
    "/cdn-cgi/challenge-platform",
)
_CAPTCHA_MARKERS = ("g-recaptcha", "h-captcha", "hcaptcha.com", "cf-turnstile")
_JUST_A_MOMENT = "<title>just a moment"
_SNIFF_BYTES = 65536
_FORBIDDEN, _TOO_MANY, _UNAVAILABLE = 403, 429, 503


def classify_http(response: Response) -> str | None:
    """Return the challenge kind of a direct HTTP response, or ``None``.

    Cloudflare also injects ``/cdn-cgi/challenge-platform`` scripts into
    ordinary pages, so body markers only count on a 403/503.
    """
    if response.status == _TOO_MANY:
        return "429"
    body = response.body[:_SNIFF_BYTES].decode("utf-8", errors="replace").lower()
    mitigated = response.headers.get("cf-mitigated", "").lower() == "challenge"
    if mitigated or _JUST_A_MOMENT in body:
        return "cloudflare"
    if response.status not in {_FORBIDDEN, _UNAVAILABLE}:
        return None
    return _refusal_kind(body, response.status)


def _refusal_kind(body: str, status: int) -> str | None:
    if any(m in body for m in _CAPTCHA_MARKERS):
        return "captcha"
    if any(m in body for m in _CF_MARKERS):
        return "cloudflare"
    return "403" if status == _FORBIDDEN else None


_MESSAGE_RULES = (
    ("captcha", re.compile(r"captcha", re.IGNORECASE)),
    ("cloudflare", re.compile(r"cloudflare", re.IGNORECASE)),
    ("429", re.compile(r"(?<!\d)429(?!\d)")),
    ("403", re.compile(r"(?<!\d)403(?!\d)")),
    ("webview", re.compile(r"cef is disabled|webview", re.IGNORECASE)),
)


def classify_message(message: str) -> str | None:
    """Return the challenge kind named by an extension error message."""
    for kind, pattern in _MESSAGE_RULES:
        if pattern.search(message):
            return kind
    return None
