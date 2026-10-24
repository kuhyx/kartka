# Copyright (c) 2026 Krzysztof Rudnicki
"""Keiyoushi/Tachiyomi extensions, run by a Suwayomi-Server over GraphQL.

The server must run with its WebView (KCEF) and FlareSolverr disabled: an
extension that needs a browser to read the site is measured as ``webview``
blocking instead of being helped past it.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
import json
from typing import TYPE_CHECKING, cast

from source_eval.challenge import classify_message
from source_eval.http import Request
from source_eval.models import Candidate, Chapter, Hit, PageImage, SourceError

if TYPE_CHECKING:
    from source_eval.http import Response
    from source_eval.polite import PoliteClient

_OK = 200
_SOURCE = "query($id:LongString!){source(id:$id){id}}"
_REFRESH = "mutation{fetchExtensions(input:{}){extensions{pkgName}}}"
_INSTALL = (
    "mutation($pkg:String!){updateExtension(input:{id:$pkg,patch:{install:true}})"
    "{extension{pkgName isInstalled}}}"
)
_LIST = (
    "mutation($s:LongString!,$t:FetchSourceMangaType!,$q:String){fetchSourceManga(input:"
    "{source:$s,type:$t,page:1,query:$q}){mangas{id title}}}"
)
_CHAPTERS = (
    "mutation($m:Int!){fetchMangaAndChapters(input:{id:$m,fetchManga:false,fetchChapters:true})"
    "{chapters{id chapterNumber}}}"
)
_PAGES = "mutation($c:Int!){fetchChapterPages(input:{chapterId:$c}){pages}}"


@dataclass(frozen=True, slots=True)
class SuwayomiConfig:
    """Where the server is and how to authenticate (basic auth or none)."""

    url: str = "http://127.0.0.1:4567"
    user: str = ""
    password: str = ""

    def headers(self) -> dict[str, str]:
        """Auth header, when credentials are configured."""
        if not self.user:
            return {}
        token = base64.b64encode(f"{self.user}:{self.password}".encode()).decode()
        return {"Authorization": f"Basic {token}"}


def _errors(response: Response) -> str | None:
    if response.status != _OK:
        return f"HTTP {response.status}: {response.text()[:300]}"
    try:
        payload = cast("dict[str, object]", response.json())
    except ValueError:
        return "non-JSON response"
    errors = cast("list[dict[str, object]]", payload.get("errors") or [])
    return str(errors[0].get("message", "error")).splitlines()[0] if errors else None


def judge_graphql(response: Response) -> tuple[bool, str | None]:
    """A GraphQL error is a failure; its message names any challenge."""
    error = _errors(response)
    return error is None, classify_message(error) if error else None


class SuwayomiBackend:
    """One Suwayomi server; requests are paced by the *source's* host."""

    def __init__(self, client: PoliteClient, config: SuwayomiConfig) -> None:
        """Use ``client`` against the server described by ``config``."""
        self._client = client
        self._config = config

    def _gql(
        self,
        query: str,
        variables: dict[str, object],
        *,
        host: str,
        record: bool = True,
    ) -> dict[str, object]:
        body = json.dumps({"query": query, "variables": variables}).encode()
        headers = {"Content-Type": "application/json", **self._config.headers()}
        request = Request(
            "POST", f"{self._config.url}/api/graphql", headers, body, timeout=60.0
        )
        response = self._client.fetch(
            request, host=host, judge=judge_graphql, record=record
        )
        error = _errors(response)
        if error is not None:
            raise SourceError(error, classify_message(error))
        return cast(
            "dict[str, object]", cast("dict[str, object]", response.json())["data"]
        )

    @staticmethod
    def _source_id(cand: Candidate) -> str:
        return cand.id.removeprefix("suwayomi:")

    def prepare(self, cand: Candidate) -> None:
        """Install the candidate's extension unless the server has it."""
        local = "suwayomi-admin"
        variables: dict[str, object] = {"id": self._source_id(cand)}
        try:
            self._gql(_SOURCE, variables, host=local, record=False)
        except SourceError:
            self._gql(_REFRESH, {}, host=local, record=False)
            self._gql(_INSTALL, {"pkg": cand.pkg}, host=local, record=False)
            self._gql(_SOURCE, variables, host=local, record=False)

    def _list(self, cand: Candidate, kind: str, query: str | None) -> list[Hit]:
        variables: dict[str, object] = {"s": self._source_id(cand), "t": kind, "q": query}
        data = self._gql(_LIST, variables, host=cand.host)
        block = cast("dict[str, object]", data["fetchSourceManga"])
        return [Hit(str(m["title"]), str(m["id"])) for m in cast("list[dict[str, object]]", block["mangas"])]

    def popular(self, cand: Candidate) -> list[Hit]:
        """First page of the extension's popular listing."""
        return self._list(cand, "POPULAR", None)

    def search(self, cand: Candidate, query: str) -> list[Hit]:
        """First page of the extension's search."""
        return self._list(cand, "SEARCH", query)

    def chapters(self, cand: Candidate, hit: Hit) -> list[Chapter]:
        """Chapter list fetched fresh from the source."""
        data = self._gql(_CHAPTERS, {"m": int(hit.ref)}, host=cand.host)
        block = cast("dict[str, object]", data["fetchMangaAndChapters"])
        out = []
        for ch in cast("list[dict[str, object]]", block["chapters"]):
            number = float(cast("float", ch["chapterNumber"]))
            out.append(Chapter(str(ch["id"]), number if number >= 0 else None))
        return out

    def pages(self, cand: Candidate, chapter: Chapter) -> list[PageImage]:
        """Page URLs served (proxied) by the server."""
        data = self._gql(_PAGES, {"c": int(chapter.ref)}, host=cand.host)
        block = cast("dict[str, object] | None", data["fetchChapterPages"])
        paths = cast("list[str]", (block or {}).get("pages", []))
        return [
            PageImage(f"{self._config.url}{p}", self._config.headers()) for p in paths
        ]

    def image(self, cand: Candidate, page: PageImage) -> bytes:
        """One page through the server, which fetches it from the source."""
        request = Request("GET", page.url, page.headers, timeout=60.0)
        response = self._client.fetch(request, host=cand.host, judge=_judge_image)
        if response.status != _OK:
            error = f"HTTP {response.status}: {response.text()[:300]}"
            raise SourceError(error, classify_message(response.text()[:300]))
        return response.body


def _judge_image(response: Response) -> tuple[bool, str | None]:
    if response.status == _OK:
        return True, None
    return False, classify_message(response.text()[:300])
