# Copyright (c) 2026 Krzysztof Rudnicki
"""MangaUpdates: chapter counts for titles AniList leaves blank (ongoing)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, cast

from source_eval.http import Request
from source_eval.match import THRESHOLD, title_score

if TYPE_CHECKING:
    from source_eval.models import RefTitle
    from source_eval.polite import PoliteClient

API = "https://api.mangaupdates.com/v1"
_OK = 200


def _json(client: PoliteClient, request: Request) -> dict[str, object] | None:
    response = client.fetch(request, cacheable=True)
    if response.status != _OK:
        return None
    return cast("dict[str, object]", response.json())


def latest_chapter(client: PoliteClient, ref: RefTitle) -> int | None:
    """Latest chapter number MangaUpdates lists for ``ref``, if it knows it."""
    body = json.dumps({"search": ref.titles[0], "perpage": 5}).encode()
    found = _json(
        client,
        Request(
            "POST", f"{API}/series/search", {"Content-Type": "application/json"}, body
        ),
    )
    for result in cast("list[dict[str, object]]", (found or {}).get("results", [])):
        record = cast("dict[str, object]", result["record"])
        hit = str(result.get("hit_title") or record["title"])
        if title_score(hit, ref.titles) < THRESHOLD:
            continue
        series = _json(client, Request("GET", f"{API}/series/{record['series_id']}"))
        latest = (series or {}).get("latest_chapter")
        return int(cast("int", latest)) if latest else None
    return None
