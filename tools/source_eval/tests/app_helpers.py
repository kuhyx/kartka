# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
from typing import TYPE_CHECKING
lazy from pathlib import Path

from source_eval.app import App, Settings
from source_eval.backends.mangadex import API
from source_eval.backends.suwayomi import SuwayomiConfig
from source_eval.candidates import catalog
from source_eval.reference import anilist, mangaupdates
from tests.fakes import FakeClock, FakeTransport, fixture_bytes, fixture_json, resp
from tests.test_reference import anilist_handler

if TYPE_CHECKING:
    from source_eval.http import Request, Response

SUWA = "http://suwa.test"


def suwa_handler(req: Request) -> Response:
    query = json.loads(req.body or b"{}")["query"]
    if "fetchSourceManga" in query:
        return resp(200, fixture_json("suwa_search_cloudflare.json"))
    return resp(200, {"data": {"source": {"id": "1"}}})


def make_app(tmp_path: Path) -> tuple[App, FakeTransport, FakeClock, list[str]]:
    clock, t = FakeClock(), FakeTransport()
    lines: list[str] = []
    t.add(catalog.KEIYOUSHI_INDEX, resp(200, fixture_bytes("keiyoushi_index.pb")))
    t.add(catalog.MANGAYOMI_INDEX, resp(200, fixture_bytes("mangayomi_index.json")))
    t.add(anilist.ENDPOINT, anilist_handler)
    t.add(
        f"{mangaupdates.API}/series/search", resp(200, fixture_json("mu_search.json"))
    )
    t.add(f"{mangaupdates.API}/series/", resp(200, fixture_json("mu_series.json")))
    t.add(f"{API}/manga?title", resp(200, fixture_json("md_search.json")))
    t.add(f"{API}/manga?limit", resp(200, fixture_json("md_search.json")))
    t.add(f"{API}/manga/", resp(200, fixture_json("md_feed.json")))
    t.add(f"{API}/at-home/", resp(200, fixture_json("md_athome.json")))
    t.add(f"{SUWA}/api/graphql", suwa_handler)
    t.add("https://mangafire.to", resp(403, "<title>Just a moment...</title>"))
    t.add(
        "https://cmdxd98sb0x3yprd.mangadex.network",
        resp(200, fixture_bytes("page.webp")),
    )
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "legacy_sources.json").write_text(
        json.dumps(
            [
                {
                    "slug": "x",
                    "name": "X",
                    "lang": "all",
                    "baseUrl": "https://legacy.test",
                }
            ]
        )
    )
    settings = Settings(
        data_dir=tmp_path / "data",
        out_dir=tmp_path / "out",
        state_dir=tmp_path / "state",
        cache_dir=tmp_path / "cache",
        suwayomi=SuwayomiConfig(SUWA),
    )
    return App(settings, clock, t, lines.append), t, clock, lines
