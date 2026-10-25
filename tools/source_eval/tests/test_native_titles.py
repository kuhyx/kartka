# Copyright (c) 2026 Krzysztof Rudnicki
"""AniList native (Japanese) titles: stored, backfilled, searched on ja sources."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING
lazy from pathlib import Path

from source_eval.budget import Deadline
from source_eval.evaluate import queries
from source_eval.match import best_hit, names
from source_eval.models import Hit, RefTitle
from source_eval.reference import anilist
from source_eval.reference.build import Reference, build
from tests.fakes import FakeClock, FakeTransport, fixture_json, resp
from tests.test_reference import anilist_handler, client_for

if TYPE_CHECKING:
    from source_eval.http import Request, Response


def test_ref_title_native_round_trip_and_old_data() -> None:
    ref = RefTitle("anilist:1", ("A", "あ"), anilist_id=1, native="あ")
    assert ref.to_json()["nativeTitle"] == "あ"
    assert RefTitle.from_json(ref.to_json()) == ref
    old = RefTitle.from_json({"key": "anilist:1", "titles": ["A"], "anilistId": 1})
    assert old.native is None  # not fetched yet
    assert RefTitle.from_json({**old.to_json(), "nativeTitle": ""}).native == ""


def test_to_ref_carries_native() -> None:
    page = fixture_json("anilist_page.json")
    assert isinstance(page, dict)
    media = page["data"]["Page"]["media"][0]
    assert anilist.to_ref(media, "anilist").native == "チェンソーマン"
    media["title"]["native"] = None
    assert anilist.to_ref(media, "anilist").native == ""  # AniList has none


def natives_handler(req: Request) -> Response:
    body = json.loads(req.body or b"{}")
    assert "id_in" in body["query"]
    ids = body["variables"]["ids"]
    media = [{"id": i, "title": {"native": f"n{i}"}} for i in ids if i != 3]
    media += [{"id": 4, "title": {"native": None}}] if 3 in ids else []
    return resp(200, {"data": {"Page": {"media": media}}})


def test_natives_batch() -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, natives_handler)
    assert anilist.natives(client_for(t, clock), [1, 3]) == {1: "n1"}
    t2 = FakeTransport()
    t2.add(anilist.ENDPOINT, resp(404, {"data": None}))
    assert anilist.natives(client_for(t2, clock), [1]) == {}


class Calls(Deadline):
    """Expires after ``left`` checks, independent of the clock."""

    def __init__(self, clock: FakeClock, left: int) -> None:
        super().__init__(clock, None)
        self.left = left

    def expired(self) -> bool:
        self.left -= 1
        return self.left < 0


def test_build_backfills_native_titles_resumably(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, natives_handler)
    path = tmp_path / "reference.json"
    ref = Reference(path, clock)
    ref.progress["anilistPage"] = 1
    ref.titles = [
        RefTitle(f"anilist:{i}", (f"T{i}",), anilist_id=i) for i in range(1, 6)
    ]
    ref.titles.append(RefTitle("sy:x", ("X",), origins=("sy",)))
    ref.titles.append(RefTitle("anilist:9", ("T9",), anilist_id=9, native="kept"))
    ref.save()
    client = client_for(t, clock)
    deadline = Calls(clock, 1)  # one batch, then out of time
    assert not build(client, Reference(path, clock), [], deadline, top=1, batch=2)
    resumed = Reference(path, clock)
    assert [r.native for r in resumed.titles[:3]] == ["n1", "n2", None]
    assert build(client, resumed, [], Deadline(clock, None), top=1, batch=2)
    done = Reference(path, clock)
    natives = [r.native for r in done.titles]
    assert natives == ["n1", "n2", "", "n4", "n5", None, "kept"]
    assert len(t.sent) == 3
    assert build(client, done, [], Deadline(clock, None), top=1, batch=2)
    assert len(t.sent) == 3  # nothing left to backfill


def test_existing_build_needs_no_backfill(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, anilist_handler)
    ref = Reference(tmp_path / "r.json", clock)
    assert build(client_for(t, clock), ref, [], Deadline(clock, None), top=3)
    assert all(r.native for r in ref.titles)


CSM = RefTitle(
    "anilist:105778",
    ("Chainsaw Man", "CSM", "Testere Adam"),
    anilist_id=105778,
    native="チェンソーマン",
)


def test_queries_put_native_first_for_japanese_sources() -> None:
    assert queries(CSM, "ja") == ["チェンソーマン", "Chainsaw Man"]
    assert queries(CSM, "en") == ["Chainsaw Man", "CSM"]
    assert queries(CSM, "all") == ["Chainsaw Man", "CSM"]
    bare = RefTitle("sy:x", ("X", "Y"), native=None)
    assert queries(bare, "ja") == ["X", "Y"]
    same = RefTitle("anilist:2", ("ドラゴン", "Dragon"), native="ドラゴン")
    assert queries(same, "ja") == ["ドラゴン", "Dragon"]


def test_matching_uses_native_titles_for_japanese_sources() -> None:
    assert names(CSM, "ja") == (*CSM.titles, "チェンソーマン")
    assert names(CSM, "en") == CSM.titles
    hits = [Hit("チェンソーマン", "j")]
    assert best_hit(hits, CSM, "ja") == hits[0]
    assert best_hit(hits, CSM) is None  # native is not in this ref's titles
