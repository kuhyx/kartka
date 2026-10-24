# Copyright (c) 2026 Krzysztof Rudnicki
"""MangaDex through its official public API (what Kartka's native source uses)."""

from __future__ import annotations

from typing import TYPE_CHECKING, cast
from urllib.parse import urlencode

from source_eval.challenge import classify_http
from source_eval.http import Request
from source_eval.models import Candidate, Chapter, Hit, PageImage, SourceError

if TYPE_CHECKING:
    from source_eval.http import Response
    from source_eval.polite import PoliteClient

API = "https://api.mangadex.org"
_RATINGS = ("safe", "suggestive", "erotica")
_FEED_LIMIT = 500
_MAX_FEED_PAGES = 6
_OK = 200


class MangaDexBackend:
    """English chapters only, external (licensed-elsewhere) links excluded."""

    def __init__(self, client: PoliteClient) -> None:
        """Use ``client`` for every request."""
        self._client = client

    def _get(self, url: str, *, cacheable: bool = True) -> Response:
        response = self._client.fetch(Request("GET", url), cacheable=cacheable)
        if response.status != _OK:
            kind = classify_http(response)
            msg = f"MangaDex HTTP {response.status} for {url}"
            raise SourceError(msg, kind)
        return response

    def _json(self, url: str) -> dict[str, object]:
        return cast("dict[str, object]", self._get(url).json())

    def prepare(self, cand: Candidate) -> None:
        """Nothing to install."""
        del cand

    def popular(self, cand: Candidate) -> list[Hit]:
        """Most-followed titles (uncached: this is the uptime probe)."""
        del cand
        url = f"{API}/manga?limit=5&order[followedCount]=desc"
        return self._hits(cast("dict[str, object]", self._get(url, cacheable=False).json()))

    def _hits(self, data: dict[str, object]) -> list[Hit]:
        hits = []
        for item in cast("list[dict[str, object]]", data["data"]):
            attrs = cast("dict[str, object]", item["attributes"])
            titles = cast("dict[str, str]", attrs["title"])
            hits.append(Hit(next(iter(titles.values()), ""), str(item["id"])))
        return hits

    def search(self, cand: Candidate, query: str) -> list[Hit]:
        """``/manga?title=`` restricted to manga with English chapters."""
        del cand
        params = [
            ("title", query),
            ("limit", "10"),
            ("availableTranslatedLanguage[]", "en"),
        ]
        params += [("contentRating[]", r) for r in _RATINGS]
        return self._hits(self._json(f"{API}/manga?{urlencode(params)}"))

    def chapters(self, cand: Candidate, hit: Hit) -> list[Chapter]:
        """The English feed, readable chapters only."""
        del cand
        out: list[Chapter] = []
        for page in range(_MAX_FEED_PAGES):
            params = {
                "translatedLanguage[]": "en",
                "limit": str(_FEED_LIMIT),
                "offset": str(page * _FEED_LIMIT),
                "includeExternalUrl": "0",
                "includeEmptyPages": "0",
                "includeFuturePublishAt": "0",
                "order[chapter]": "asc",
            }
            data = self._json(f"{API}/manga/{hit.ref}/feed?{urlencode(params)}")
            for item in cast("list[dict[str, object]]", data["data"]):
                attrs = cast("dict[str, object]", item["attributes"])
                if attrs.get("externalUrl"):
                    continue
                number = attrs.get("chapter")
                out.append(Chapter(str(item["id"]), _float(number)))
            if (page + 1) * _FEED_LIMIT >= int(cast("int", data["total"])):
                break
        return out

    def pages(self, cand: Candidate, chapter: Chapter) -> list[PageImage]:
        """Full-quality page URLs from the MangaDex@Home node."""
        del cand
        data = self._json(f"{API}/at-home/server/{chapter.ref}")
        info = cast("dict[str, object]", data["chapter"])
        base = f"{data['baseUrl']}/data/{info['hash']}"
        return [PageImage(f"{base}/{name}") for name in cast("list[str]", info["data"])]

    def image(self, cand: Candidate, page: PageImage) -> bytes:
        """Image bytes (never cached: they are big and only measured once)."""
        del cand
        return self._get(page.url, cacheable=False).body


def _float(value: object) -> float | None:
    try:
        return float(str(value))
    except ValueError:
        return None
