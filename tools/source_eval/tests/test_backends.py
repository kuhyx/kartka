from __future__ import annotations

import json

import pytest

from source_eval.backends.mangadex import API, MangaDexBackend
from source_eval.backends.plugin import PluginBackend
from source_eval.backends.suwayomi import SuwayomiBackend, SuwayomiConfig, judge_graphql
from source_eval.http import Request, Response
from source_eval.models import Candidate, Chapter, Hit, PageImage, SourceError
from source_eval.polite import HostGate, Observation, PoliteClient
from tests.fakes import FakeClock, FakeTransport, fixture_bytes, fixture_json, resp

MD = Candidate("mangadex", "MangaDex", "en", "native", "https://mangadex.org")
DOT = Candidate(
    "suwayomi:5900936305360403385", "MangaDot", "en", "suwayomi", "https://mangadot.net",
    pkg="eu.kanade.tachiyomi.extension.en.mangadotnet",
)  # fmt: skip
SUWA = "http://suwa.test"


def client(t: FakeTransport, seen: list[Observation] | None = None) -> PoliteClient:
    clock = FakeClock()
    sink = seen.append if seen is not None else None
    return PoliteClient(t, HostGate(None, 2.0, clock), clock, None, "ua", observe=sink)


def test_mangadex_flow() -> None:
    t = FakeTransport()
    t.add(f"{API}/manga?", resp(200, fixture_json("md_search.json")))
    t.add(f"{API}/manga/", resp(200, fixture_json("md_feed.json")))
    t.add(f"{API}/at-home/", resp(200, fixture_json("md_athome.json")))
    t.add("https://", resp(200, fixture_bytes("page.webp")))
    md = MangaDexBackend(client(t))
    md.prepare(MD)
    hits = md.search(MD, "Yotsuba")
    assert Hit("Yotsuba to!", "58be6aa6-06cb-4ca5-bd20-f1392ce451fb") in hits
    chapters = md.chapters(MD, hits[1])
    assert len(chapters) == 8
    assert chapters[0].number == 1.0
    pages = md.pages(MD, chapters[0])
    assert len(pages) == 5
    assert "/data/" in pages[0].url
    assert md.image(MD, pages[0]).startswith(b"RIFF")


def test_mangadex_feed_paging_externals_and_errors() -> None:
    t = FakeTransport()
    big = {
        "total": 600,
        "data": [
            {"id": "a", "attributes": {"chapter": None, "externalUrl": None}},
            {"id": "b", "attributes": {"chapter": "2", "externalUrl": "https://x"}},
        ],
    }
    t.add(f"{API}/manga/m/feed", resp(200, big))
    md = MangaDexBackend(client(t))
    out = md.chapters(MD, Hit("t", "m"))
    assert out == [Chapter("a", None), Chapter("a", None)]
    t2 = FakeTransport()
    t2.add(API, resp(429, "slow down", {"retry-after": "0"}))
    with pytest.raises(SourceError) as err:
        MangaDexBackend(client(t2)).search(MD, "x")
    assert err.value.kind == "429"


def gql_router(responses: dict[str, object]) -> FakeTransport:
    t = FakeTransport()

    def handle(req: Request) -> Response:
        query = json.loads(req.body or b"{}")["query"]
        for needle, body in responses.items():
            if needle in query:
                return resp(200, body)
        return resp(200, {"errors": [{"message": "unexpected"}]})

    t.add(f"{SUWA}/api/graphql", handle)
    t.add(f"{SUWA}/api/v1/", resp(200, fixture_bytes("page.webp")))
    return t


def test_suwayomi_flow_and_pacing_key() -> None:
    seen: list[Observation] = []
    t = gql_router(
        {
            "source(id": {"data": {"source": {"id": "1"}}},
            "fetchSourceManga": fixture_json("suwa_search.json"),
            "fetchMangaAndChapters": fixture_json("suwa_chapters.json"),
            "fetchChapterPages": fixture_json("suwa_pages.json"),
        }
    )
    sw = SuwayomiBackend(client(t, seen), SuwayomiConfig(SUWA, "kuhy", "pw"))
    sw.prepare(DOT)
    hits = sw.search(DOT, "Berserk")
    assert hits[0] == Hit("Berserk Gaiden", "21")
    chapters = sw.chapters(DOT, hits[0])
    assert chapters[0].number == 1.0
    pages = sw.pages(DOT, chapters[0])
    assert pages[0].url == f"{SUWA}/api/v1/manga/21/chapter/1/page/0"
    assert pages[0].headers["Authorization"].startswith("Basic ")
    assert sw.image(DOT, pages[0]).startswith(b"RIFF")
    assert {o.host for o in seen} == {"mangadot.net"}  # admin calls not recorded
    assert all(o.ok for o in seen)


def test_suwayomi_installs_missing_extension() -> None:
    calls: list[str] = []
    state = {"installed": False}
    t = FakeTransport()

    def handle(req: Request) -> Response:
        body = json.loads(req.body or b"{}")
        calls.append(body["query"].split("{")[0] + json.dumps(body["variables"]))
        if "updateExtension" in body["query"]:
            state["installed"] = True
        if "source(id" in body["query"] and not state["installed"]:
            return resp(200, fixture_json("suwa_source_missing.json"))
        return resp(200, {"data": {"ok": True}})

    t.add(SUWA, handle)
    SuwayomiBackend(client(t), SuwayomiConfig(SUWA)).prepare(DOT)
    assert any(DOT.pkg in c for c in calls)
    assert len(calls) == 4


def test_suwayomi_errors_are_classified() -> None:
    seen: list[Observation] = []
    t = gql_router({"fetchChapterPages": fixture_json("suwa_pages_cef_error.json")})
    sw = SuwayomiBackend(client(t, seen), SuwayomiConfig(SUWA))
    with pytest.raises(SourceError) as err:
        sw.pages(DOT, Chapter("428", 1.0))
    assert err.value.kind == "webview"
    assert seen[-1].kind == "webview"
    assert not seen[-1].ok
    t2 = FakeTransport()
    t2.add(f"{SUWA}/api/v1/", resp(500, "HTTP error 403"))
    with pytest.raises(SourceError) as err2:
        SuwayomiBackend(client(t2), SuwayomiConfig(SUWA)).image(
            DOT, PageImage(f"{SUWA}/api/v1/x")
        )
    assert err2.value.kind == "403"
    t3 = FakeTransport()
    t3.add(SUWA, resp(200, {"data": {"fetchChapterPages": None}}))
    assert (
        SuwayomiBackend(client(t3), SuwayomiConfig(SUWA)).pages(DOT, Chapter("1", None))
        == []
    )


def test_judge_graphql() -> None:
    assert judge_graphql(resp(200, {"data": {}})) == (True, None)
    assert judge_graphql(resp(502, "Bad gateway")) == (False, None)
    assert judge_graphql(resp(200, "<html>")) == (False, None)
    bad = {"errors": [{"message": "Failed to bypass Cloudflare\nstack"}]}
    assert judge_graphql(resp(200, bad)) == (False, "cloudflare")
    assert SuwayomiConfig().headers() == {}


def test_suwayomi_unknown_chapter_number() -> None:
    body = {"data": {"fetchMangaAndChapters": {"chapters": [{"id": 5, "chapterNumber": -1.0}]}}}
    t = gql_router({"fetchMangaAndChapters": body})
    assert SuwayomiBackend(client(t), SuwayomiConfig(SUWA)).chapters(
        DOT, Hit("x", "3")
    ) == [Chapter("5", None)]


def test_plugin_stub() -> None:
    p = PluginBackend()
    cand = Candidate("plugin:x", "x", "en", "plugin", "https://x")
    for call in (
        lambda: p.prepare(cand),
        lambda: p.search(cand, "q"),
        lambda: p.chapters(cand, Hit("t", "r")),
        lambda: p.pages(cand, Chapter("c", 1.0)),
        lambda: p.image(cand, PageImage("u")),
    ):
        with pytest.raises(SourceError, match="no headless plugin runtime"):
            call()
