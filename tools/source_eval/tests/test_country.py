# Copyright (c) 2026 Krzysztof Rudnicki
"""Rating counts Japanese manga only (kuhy, 2026-11-20): no manhwa, no manhua."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, cast
lazy from pathlib import Path

import pytest

from source_eval.budget import Deadline
from source_eval.candidates import catalog
from source_eval.country import JAPAN, japanese, jp_manifest
from source_eval.models import Candidate, RefTitle
from source_eval.reference import anilist
from source_eval.reference.build import Reference, build
from source_eval.state import Manifest, RunDir
from tests.app_helpers import make_app
from tests.fakes import FakeClock, FakeTransport, fixture_json, resp
from tests.test_native_titles import Calls
from tests.test_reference import client_for

if TYPE_CHECKING:
    from source_eval.http import Request, Response

CAND = Candidate("suwayomi:1", "Fake", "en", "suwayomi", "https://fake.test", "eu.x")


def ref(key: str, country: str | None) -> RefTitle:
    return RefTitle(key, (key,), anilist_id=None, country=country)


def test_ref_title_country_round_trip_and_old_data() -> None:
    title = RefTitle("anilist:1", ("A",), anilist_id=1, native="", country="JP")
    assert title.to_json()["countryOfOrigin"] == "JP"
    assert RefTitle.from_json(title.to_json()) == title
    old = RefTitle.from_json({"key": "anilist:1", "titles": ["A"], "anilistId": 1})
    assert old.country is None  # not fetched yet


def test_to_ref_carries_the_country() -> None:
    page = cast(
        "dict[str, dict[str, dict[str, object]]]", fixture_json("anilist_page.json")
    )
    media = cast("list[dict[str, object]]", page["data"]["Page"]["media"])
    assert [anilist.to_ref(m, "anilist").country for m in media] == ["JP", "KR", "JP"]
    media[0].pop("countryOfOrigin")
    assert anilist.to_ref(media[0], "anilist").country == ""  # AniList has none


def test_japanese_keeps_order_and_drops_other_or_unknown() -> None:
    titles = [ref("a", "JP"), ref("b", "KR"), ref("c", None), ref("d", "")]
    titles += [ref("e", "CN"), ref("f", JAPAN)]
    assert japanese(titles) == ["a", "f"]
    manifest = Manifest(["f", "b", "a", "gone"], 1, 1, 1, all_chapters=True)
    assert jp_manifest(manifest, titles).sample == ["f", "a"]


def top_jp_handler(req: Request) -> Response:
    body = json.loads(req.body or b"{}")
    assert "countryOfOrigin:JP" in body["query"]
    page = body["variables"]["page"]
    media = [
        {
            "id": page * 10 + i,
            "title": {"romaji": f"T{page}-{i}"},
            "countryOfOrigin": "JP",
        }
        for i in range(body["variables"]["perPage"])
    ]
    return resp(
        200, {"data": {"Page": {"pageInfo": {"hasNextPage": True}, "media": media}}}
    )


def test_new_build_queries_japan_only_and_fills_the_size(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, top_jp_handler)
    path = tmp_path / "reference.json"
    old = Reference(path, clock)
    old.progress = {"anilistPage": 10}  # an old, unfiltered build was complete
    old.titles = [
        RefTitle("anilist:11", ("T1-1",), anilist_id=11, native="", country="JP")
    ]
    old.save()
    ref_ = Reference(path, clock)
    assert build(
        client_for(t, clock), ref_, [], Deadline(clock, None), top=5, per_page=2
    )
    assert len(japanese(ref_.titles)) == 5
    assert len(t.sent) == 3  # pages 1-3 of the Japan-only query, no backfill
    again = Reference(path, clock)
    assert build(
        client_for(t, clock), again, [], Deadline(clock, None), top=5, per_page=2
    )
    assert len(t.sent) == 3  # complete: nothing refetched


def details_handler(req: Request) -> Response:
    body = json.loads(req.body or b"{}")
    assert "id_in" in body["query"]
    assert "countryOfOrigin" in body["query"]
    media = [
        {
            "id": i,
            "title": {"native": f"n{i}"},
            "countryOfOrigin": "KR" if i == 2 else "JP",
        }
        for i in body["variables"]["ids"]
        if i != 3  # AniList returns nothing for 3
    ]
    return resp(200, {"data": {"Page": {"media": media}}})


def test_backfill_fills_country_and_native_resumably(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, details_handler)
    path = tmp_path / "reference.json"
    ref_ = Reference(path, clock)
    ref_.progress = {"anilistJpPage": 1}
    ref_.titles = [
        RefTitle(f"anilist:{i}", (f"T{i}",), anilist_id=i) for i in (1, 2, 3)
    ]
    ref_.titles.append(RefTitle("anilist:4", ("T4",), anilist_id=4, native="kept"))
    ref_.titles.append(RefTitle("sy:x", ("X",), origins=("sy",)))
    ref_.save()
    client = client_for(t, clock)
    assert not build(
        client, Reference(path, clock), [], Calls(clock, 1), top=1, batch=2
    )
    resumed = Reference(path, clock)
    assert [r.country for r in resumed.titles[:3]] == ["JP", "KR", None]
    assert build(client, resumed, [], Deadline(clock, None), top=1, batch=2)
    done = Reference(path, clock)
    assert [r.country for r in done.titles] == ["JP", "KR", "", "JP", None]
    assert [r.native for r in done.titles] == ["n1", "n2", "", "kept", None]
    assert len(t.sent) == 2
    assert build(client, done, [], Deadline(clock, None), top=1, batch=2)
    assert len(t.sent) == 2  # "" is fetched: no endless backfill


def test_details_batch_and_missing_page() -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(anilist.ENDPOINT, details_handler)
    assert anilist.details(client_for(t, clock), [2, 3]) == {2: ("n2", "KR")}
    t2 = FakeTransport()
    t2.add(anilist.ENDPOINT, resp(404, {"data": None}))
    assert anilist.details(client_for(t2, clock), [1]) == {}


def test_init_run_samples_japanese_titles_only(tmp_path: Path) -> None:
    app, _, _, _ = make_app(tmp_path)
    ref_ = app.reference()
    ref_.titles = [ref("a", "JP"), ref("b", "KR"), ref("c", "JP"), ref("d", None)]
    ref_.save()
    assert app.cmd_init_run("r", None, Manifest([], 1, 1, 1)) == 0
    manifest = Manifest.load(RunDir(app.s.state_dir, "r").manifest_path)
    assert manifest is not None
    assert manifest.sample == ["a", "c"]


@pytest.mark.usefixtures("no_rejects")
def test_report_rescores_a_stored_run_on_japanese_titles(tmp_path: Path) -> None:
    app, _, _, lines = make_app(tmp_path)
    catalog.save(app.candidates_path, [CAND])
    ref_ = app.reference()
    ref_.titles = [ref("a", "JP"), ref("b", "KR"), ref("c", "JP"), ref("d", None)]
    ref_.save()
    run = RunDir(app.s.state_dir, "r")
    Manifest(["a", "b", "c", "d"], 1, 1, 1, all_chapters=True).save(run.manifest_path)
    state = run.source(CAND.id)
    state.titles = {k: {"status": "found"} for k in ("a", "b", "d")}
    state.titles["c"] = {"status": "missing"}
    state.chapters = {k: {"count": 9, "ratio": 1.0} for k in ("a", "b", "d")}
    state.done = True
    state.save()
    out = tmp_path / "out.json"
    assert app.cmd_report("r", out, None) == 0
    report = json.loads(out.read_text())
    assert report["referenceSize"] == 2
    coverage = report["sources"][0]["coverage"]
    assert coverage == {
        "referenceSize": 2,
        "found": 1,
        "ratio": 0.5,
        "complete": 1,
        "completeRatio": 0.5,
    }
    assert report["sources"][0]["chapterCompleteness"]["sampled"] == 1
    assert "reference: 2 Japanese of 4 sample titles" in lines
