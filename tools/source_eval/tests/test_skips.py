# Copyright (c) 2026 Krzysztof Rudnicki
"""English + Japanese candidates, and every dropped index entry with its reason."""

from __future__ import annotations

lazy from pathlib import Path

from source_eval.candidates import catalog
from source_eval.candidates.indexes import (
    KEEP_LANGS,
    MangayomiEntry,
    parse_keiyoushi,
    parse_mangayomi,
)
from source_eval.models import Candidate
from tests.fakes import fixture_bytes, fixture_json


def kei(
    sid: int, lang: str, url: str, name: str = "", catalog: str = "keiyoushi"
) -> Candidate:
    return Candidate(
        f"suwayomi:{sid}",
        name or f"K{sid}",
        lang,
        "suwayomi",
        url,
        pkg="p",
        catalogs=(catalog,),
    )


def yomi(sid: str, lang: str, url: str, *, js: bool = True) -> MangayomiEntry:
    return MangayomiEntry(sid, f"Y{sid}", lang, url, js)


def test_keep_langs_are_english_and_japanese() -> None:
    assert {"en", "ja", "all"} == KEEP_LANGS


def test_parse_keiyoushi_keeps_every_language() -> None:
    langs = {c.lang for c in parse_keiyoushi(fixture_bytes("keiyoushi_index.pb"))}
    assert langs == {"all", "en", "es", "ja", "ko", "zh"}


def test_merge_keeps_japanese_and_records_skips() -> None:
    keiyoushi = [
        kei(1, "en", "https://a.test"),
        kei(2, "ja", "https://raw.test"),
        kei(3, "es", "https://es.test", "Spanish"),
        kei(4, "ko", "https://ko.test", "Korean"),
        kei(1, "en", "https://a.test"),  # same id twice
    ]
    mangayomi = [
        yomi("10", "ja", "https://jp.test"),
        yomi("11", "fr", "https://fr.test"),
        yomi("12", "en", "https://dart.test", js=False),
        yomi("13", "en", "https://a.test"),  # Keiyoushi covers a.test
        yomi("14", "en", "https://mangadex.org"),  # native covers it
        yomi("15", "ja", "https://jp.test"),  # same domain + lang as 10
    ]
    legacy = [kei(2, "ja", "https://raw.test", "Legacy dup", "sy-backup")]
    cands, skipped = catalog.merge_report(keiyoushi, mangayomi, legacy)
    ids = [c.id for c in cands]
    assert ids == ["mangadex", "suwayomi:1", "suwayomi:2", "plugin:mangayomi-10"]
    assert skipped == [
        {
            "index": "keiyoushi",
            "reason": "language",
            "count": 2,
            "names": ["Korean", "Spanish"],
        },
        {"index": "keiyoushi", "reason": "duplicate", "count": 1, "names": ["K1"]},
        {"index": "mangayomi", "reason": "language", "count": 1, "names": ["Y11"]},
        {"index": "mangayomi", "reason": "dart", "count": 1, "names": ["Y12"]},
        {
            "index": "mangayomi",
            "reason": "domain-overlap",
            "count": 2,
            "names": ["Y13", "Y14"],
        },
        {"index": "mangayomi", "reason": "duplicate", "count": 1, "names": ["Y15"]},
        {
            "index": "sy-backup",
            "reason": "duplicate",
            "count": 1,
            "names": ["Legacy dup"],
        },
    ]
    total_in = len(keiyoushi) + len(mangayomi) + len(legacy) + 1  # + native
    kept_plus_skipped = len(cands) + sum(int(str(s["count"])) for s in skipped)
    assert kept_plus_skipped == total_in


def test_language_wins_over_dart_and_overlap() -> None:
    _, skipped = catalog.merge_report(
        [kei(1, "en", "https://a.test")],
        [yomi("1", "de", "https://a.test", js=False)],
    )
    assert [(s["index"], s["reason"]) for s in skipped] == [("mangayomi", "language")]


def test_fixture_conservation() -> None:
    k = parse_keiyoushi(fixture_bytes("keiyoushi_index.pb"))
    m = parse_mangayomi(fixture_json("mangayomi_index.json"))
    cands, skipped = catalog.merge_report(k, m)
    assert (
        len(cands) + sum(int(str(s["count"])) for s in skipped) == len(k) + len(m) + 1
    )
    assert {c.lang for c in cands} <= KEEP_LANGS
    assert "suwayomi:" + "2499283573021220255" in {c.id for c in cands}
    assert catalog.merge(k, m) == cands


def test_skipped_round_trip(tmp_path: Path) -> None:
    path = tmp_path / "skipped.json"
    assert catalog.load_skipped(path) == []
    rows: list[dict[str, object]] = [
        {"index": "keiyoushi", "reason": "language", "count": 1, "names": ["X"]}
    ]
    catalog.save_skipped(path, rows)
    assert catalog.load_skipped(path) == rows
