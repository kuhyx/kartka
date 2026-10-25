# Copyright (c) 2026 Krzysztof Rudnicki
"""AniList GraphQL: the popularity-ranked reference titles."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, cast

from source_eval.http import Request
from source_eval.match import THRESHOLD, title_score
from source_eval.models import RefTitle

if TYPE_CHECKING:
    from source_eval.polite import PoliteClient

ENDPOINT = "https://graphql.anilist.co"
_FIELDS = "id title{romaji english native} synonyms chapters status format"
_TOP = (
    "query($page:Int,$perPage:Int){Page(page:$page,perPage:$perPage){"
    "pageInfo{hasNextPage} media(type:MANGA,sort:POPULARITY_DESC,format_not:NOVEL){"
    + _FIELDS
    + "}}}"
)
_SEARCH = (
    "query($q:String){Media(search:$q,type:MANGA,format_not:NOVEL){" + _FIELDS + "}}"
)
_NATIVES = (
    "query($ids:[Int]){Page(perPage:50){"
    "media(id_in:$ids,type:MANGA){id title{native}}}}"
)
_OK, _NOT_FOUND = 200, 404


class AniListError(RuntimeError):
    """AniList answered with something other than data."""


def _post(
    client: PoliteClient, query: str, variables: dict[str, object]
) -> dict[str, object] | None:
    body = json.dumps({"query": query, "variables": variables}).encode()
    response = client.fetch(
        Request("POST", ENDPOINT, {"Content-Type": "application/json"}, body),
        cacheable=True,
    )
    if response.status == _NOT_FOUND:
        return None
    if response.status != _OK:
        msg = f"AniList HTTP {response.status}"
        raise AniListError(msg)
    return cast("dict[str, object]", cast("dict[str, object]", response.json())["data"])


def to_ref(media: dict[str, object], origin: str) -> RefTitle:
    """Map one AniList ``Media`` to a reference title."""
    names = cast("dict[str, str | None]", media["title"])
    titles = [names.get("english"), names.get("romaji"), names.get("native")]
    titles += cast("list[str]", media.get("synonyms") or [])
    unique = list(dict.fromkeys(t for t in titles if t))
    chapters = cast("int | None", media.get("chapters"))
    return RefTitle(
        key=f"anilist:{media['id']}",
        titles=tuple(unique),
        chapters=chapters,
        chapters_from="anilist" if chapters else None,
        anilist_id=int(cast("int", media["id"])),
        origins=(origin,),
        native=names.get("native") or "",
    )


def top_page(
    client: PoliteClient, page: int, per_page: int = 50
) -> tuple[list[RefTitle], bool]:
    """One page of the most popular manga, and whether another follows."""
    data = _post(client, _TOP, {"page": page, "perPage": per_page})
    if data is None:
        return [], False
    block = cast("dict[str, object]", data["Page"])
    media = cast("list[dict[str, object]]", block["media"])
    has_next = bool(cast("dict[str, object]", block["pageInfo"])["hasNextPage"])
    return [to_ref(m, "anilist") for m in media], has_next


def search(client: PoliteClient, title: str) -> RefTitle | None:
    """AniList's best match for ``title``, if it really is that title."""
    data = _post(client, _SEARCH, {"q": title})
    media = cast("dict[str, object] | None", data and data.get("Media"))
    if media is None:
        return None
    ref = to_ref(media, "sy")
    return ref if title_score(title, ref.titles) >= THRESHOLD else None


def natives(client: PoliteClient, ids: list[int]) -> dict[int, str]:
    """Native-script titles of up to 50 AniList ids (absent: AniList has none)."""
    data = _post(client, _NATIVES, {"ids": ids})
    if data is None:
        return {}
    page = cast("dict[str, object]", data["Page"])
    out: dict[int, str] = {}
    for media in cast("list[dict[str, object]]", page["media"]):
        native = cast("dict[str, str | None]", media["title"]).get("native")
        if native:
            out[int(cast("int", media["id"]))] = native
    return out
