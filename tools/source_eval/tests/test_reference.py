# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import json
from typing import TYPE_CHECKING
lazy from pathlib import Path

from hypothesis import given
from hypothesis import strategies as st
import pytest

from source_eval.budget import Deadline, stratified
from source_eval.match import best_hit, normalize, similarity
from source_eval.models import Hit, RefTitle
from source_eval.polite import HostGate, PoliteClient
from source_eval.reference import anilist, mangaupdates
from source_eval.reference.build import (
    Reference,
    build,
    enrich_chapters,
    load_sy_titles,
)
from tests.fakes import FakeClock, FakeTransport, fixture_json, resp

if TYPE_CHECKING:
    from source_eval.http import Request, Response


def client_for(t: FakeTransport, clock: FakeClock) -> PoliteClient:
    return PoliteClient(t, HostGate(None, 2.0, clock), clock, None, "ua")


def test_normalize_and_similarity() -> None:
    assert normalize("The Yotsuba&!") == "yotsuba and"
    assert normalize("Pokémon") == "pokemon"
    assert similarity("Berserk", "BERSERK!") == 1.0
    assert similarity("Berserk", "Berserk of Gluttony") < 0.9
    assert similarity("!!!", "x") == 0.0
    ref = RefTitle("k", ("Chainsaw Man", "CSM"))
    hits = [
        Hit("Chainsaw Man Colored", "a"),
        Hit("chainsaw man", "b"),
        Hit("Chainsaw-Man", "c"),
    ]
    best = best_hit(hits, ref)
    assert best is not None
    assert best.ref == "b"
    assert best_hit([Hit("Other", "z")], ref) is None


@given(st.text())
def test_normalize_idempotent(text: str) -> None:
    assert normalize(normalize(text)) == normalize(text)


@given(st.text(min_size=1).filter(lambda s: normalize(s) != ""))
def test_self_similarity(text: str) -> None:
    assert similarity(text, text) == 1.0


def test_stratified_and_deadline() -> None:
    items = [str(i) for i in range(10)]
    assert stratified(items, 3) == ["0", "3", "6"]
    assert stratified(items, None) == items
    assert stratified(items, 20) == items
    assert stratified(items, 0) == []
    clock = FakeClock()
    d = Deadline(clock, 5)
    assert not d.expired()
    clock.advance(5)
    assert d.expired()
    assert not Deadline(clock, None).expired()


def anilist_handler(req: Request) -> Response:
    body = json.loads(req.body or b"{}")
    if "Page" in body["query"]:
        return resp(200, fixture_json("anilist_page.json"))
    return resp(200, fixture_json("anilist_search.json"))


def test_anilist_top_and_search() -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, anilist_handler)
    titles, more = anilist.top_page(client_for(t, clock), 1, 3)
    assert more
    assert titles[0].titles[0] == "Chainsaw Man"
    assert titles[0].chapters == 232
    assert titles[0].chapters_from == "anilist"
    found = anilist.search(client_for(t, clock), "Yotsuba to!")
    assert found is not None
    assert found.chapters is None
    assert found.origins == ("sy",)
    assert anilist.search(client_for(t, clock), "Totally different") is None


def test_anilist_errors() -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, resp(404, {"data": None}))
    assert anilist.top_page(client_for(t, clock), 1) == ([], False)
    assert anilist.search(client_for(t, clock), "x") is None
    t2 = FakeTransport()
    t2.add(anilist.ENDPOINT, resp(500, "x"))
    with pytest.raises(anilist.AniListError):
        anilist.top_page(client_for(t2, clock), 1)
    t3 = FakeTransport()
    t3.add(anilist.ENDPOINT, resp(200, {"data": {"Media": None}}))
    assert anilist.search(client_for(t3, clock), "x") is None


def mu_transport() -> FakeTransport:
    t = FakeTransport()
    t.add(
        f"{mangaupdates.API}/series/search", resp(200, fixture_json("mu_search.json"))
    )
    t.add(f"{mangaupdates.API}/series/", resp(200, fixture_json("mu_series.json")))
    return t


def test_mangaupdates_latest() -> None:
    clock = FakeClock()
    client = client_for(mu_transport(), clock)
    assert mangaupdates.latest_chapter(client, RefTitle("k", ("ONE PIECE",))) == 1196
    assert mangaupdates.latest_chapter(client, RefTitle("k", ("Nope Nope",))) is None
    t = FakeTransport()
    t.add(mangaupdates.API, resp(503, "down"))
    assert (
        mangaupdates.latest_chapter(client_for(t, clock), RefTitle("k", ("One Piece",)))
        is None
    )
    t2 = FakeTransport()
    t2.add(
        f"{mangaupdates.API}/series/search", resp(200, fixture_json("mu_search.json"))
    )
    t2.add(f"{mangaupdates.API}/series/", resp(200, {"latest_chapter": None}))
    assert (
        mangaupdates.latest_chapter(
            client_for(t2, clock), RefTitle("k", ("One Piece",))
        )
        is None
    )


def test_build_resumes_and_merges_sy(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, anilist_handler)
    client = client_for(t, clock)
    path = tmp_path / "reference.json"
    ref = Reference(path, clock)
    assert not build(
        client, ref, ["Yotsuba&!", "Chainsaw Man", "Unknown Thing"], Deadline(clock, 0)
    )
    ref = Reference(path, clock)
    assert not build(client, ref, ["Yotsuba&!"], Deadline(clock, 1), top=6, per_page=3)
    ref = Reference(path, clock)
    sy = ["Yotsuba&!", "Chainsaw Man", "Unknown Thing"]
    assert build(client, ref, sy, Deadline(clock, None), top=5, per_page=3)
    assert build(client, Reference(path, clock), sy, Deadline(clock, 0))
    saved = json.loads(path.read_text())
    keys = [x["key"] for x in saved["titles"]]
    assert keys[:3] == ["anilist:105778", "anilist:105398", keys[2]]
    assert saved["referenceSize"] == len(keys)
    assert "anilist:30104" in keys
    assert "sy:unknown thing" in keys


def test_build_stops_when_anilist_runs_out(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    page = fixture_json("anilist_page.json")
    assert isinstance(page, dict)
    page["data"]["Page"]["pageInfo"]["hasNextPage"] = False
    t.add(anilist.ENDPOINT, resp(200, page))
    ref = Reference(tmp_path / "r.json", clock)
    assert build(
        client_for(t, clock), ref, [], Deadline(clock, None), top=500, per_page=3
    )
    assert len(ref.titles) == 3
    assert not build(
        client_for(t, clock),
        Reference(tmp_path / "s.json", clock),
        ["x"],
        Deadline(clock, 0),
        top=0,
    )


def test_enrich_chapters(tmp_path: Path) -> None:
    clock = FakeClock()
    ref = Reference(tmp_path / "r.json", clock)
    ref.titles = [
        RefTitle("a", ("One Piece",)),
        RefTitle("b", ("Zzz",)),
        RefTitle("c", ("Q",), 5, "anilist"),
    ]
    client = client_for(mu_transport(), clock)
    assert not enrich_chapters(client, ref, None, Deadline(clock, 0))
    assert enrich_chapters(client, ref, ["a"], Deadline(clock, None))
    assert ref.titles[0].chapters == 1196
    assert ref.titles[1].chapters_from is None
    assert enrich_chapters(client, ref, None, Deadline(clock, None))
    assert ref.titles[1].chapters_from == "none"


def test_load_sy_titles(tmp_path: Path) -> None:
    p = tmp_path / "sy.json"
    assert load_sy_titles(p) == []
    p.write_text(json.dumps(["A", {"title": " B "}, {"x": 1}, "", 3]))
    assert load_sy_titles(p) == ["A", "B"]
