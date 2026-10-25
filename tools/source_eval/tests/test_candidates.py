# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

lazy from pathlib import Path

from hypothesis import given
from hypothesis import strategies as st
import pytest

from source_eval import protowire as pw
from source_eval.candidates import catalog
from source_eval.candidates.indexes import parse_keiyoushi, parse_mangayomi
from source_eval.gate import HostGate
from source_eval.http import Request
from source_eval.models import Availability, Candidate, base_domain
from source_eval.polite import PoliteClient
from tests.fakes import FakeClock, FakeTransport, fixture_bytes, fixture_json, resp


def _varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b, n = n & 0x7F, n >> 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _encode(fields: list[tuple[int, int | bytes]]) -> bytes:
    out = b""
    for num, val in fields:
        if isinstance(val, int):
            out += _varint(num << 3) + _varint(val)
        else:
            out += _varint(num << 3 | 2) + _varint(len(val)) + val
    return out


@given(
    st.lists(
        st.tuples(
            st.integers(1, 1000),
            st.one_of(st.integers(0, 2**64 - 1), st.binary(max_size=40)),
        ),
        max_size=12,
    )
)
def test_protowire_round_trip(fields: list[tuple[int, int | bytes]]) -> None:
    assert list(pw.iter_fields(_encode(fields))) == fields


def test_protowire_fixed_and_errors() -> None:
    fixed = _varint(1 << 3 | 1) + b"12345678" + _varint(2 << 3 | 5) + b"abcd"
    assert list(pw.iter_fields(fixed)) == [(1, b"12345678"), (2, b"abcd")]
    for bad in (b"\x80", _varint(3 << 3 | 3), _varint(1 << 3 | 2) + b"\x05ab"):
        with pytest.raises(ValueError, match=r"truncated|unsupported"):
            list(pw.iter_fields(bad))
    grouped = pw.group(_encode([(1, 5), (2, b"x")]))
    assert pw.text(grouped, 1, "d") == "d"
    assert pw.text(grouped, 2) == "x"
    assert pw.integer(grouped, 2, 7) == 7
    assert pw.integer(grouped, 9) == 0


def test_parse_keiyoushi_fixture() -> None:
    cands = parse_keiyoushi(fixture_bytes("keiyoushi_index.pb"))
    ids = {c.id: c for c in cands}
    assert "suwayomi:2499283573021220255" in ids  # MangaDex en, the contract id
    assert "suwayomi:4709139914729853090" in ids  # AllManga
    assert ids["suwayomi:4709139914729853090"].installed
    assert any("rawkuma" in c.pkg for c in cands)  # ja is a candidate language
    assert {c.host for c in cands if "hdoujin" in c.pkg} == {"hdoujin.org"}


def test_parse_keiyoushi_uncompressed() -> None:
    ext = _encode(
        [
            (2, b"eu.x.en.foo"),
            (8, _encode([(1, 9), (2, b"Foo"), (3, b"en"), (4, b"https://foo.io")])),
        ]
    )
    raw = _encode([(1, b"repo"), (101, _encode([(1, ext)]))])
    assert parse_keiyoushi(raw)[0].id == "suwayomi:9"


def test_parse_mangayomi_fixture() -> None:
    entries = parse_mangayomi(fixture_json("mangayomi_index.json"))
    assert any(e.js and "mangafire" in e.base_url for e in entries)
    assert any(not e.js for e in entries)
    assert parse_mangayomi([{"id": 1, "name": "n", "isManga": False}]) == []
    with pytest.raises(TypeError):
        parse_mangayomi({})


def test_merge_availability() -> None:
    kei = parse_keiyoushi(fixture_bytes("keiyoushi_index.pb"))
    merged = catalog.merge(kei, parse_mangayomi(fixture_json("mangayomi_index.json")))
    by_id = {c.id: c for c in merged}
    assert merged[0].id == "mangadex"
    assert by_id["mangadex"].availability == Availability(
        native=True, mangayomi_js=True, keiyoushi=True
    )
    allanime = by_id["suwayomi:4709139914729853090"].availability
    assert allanime == Availability(native=False, mangayomi_js=False, keiyoushi=True)
    plugins = [c for c in merged if c.origin == "plugin"]
    assert [base_domain(c.base_url) for c in plugins] == ["mangafire.to"]
    assert plugins[0].availability == Availability(mangayomi_js=True)
    dup = catalog.merge([*kei, kei[0]], [])
    assert dup == catalog.merge(kei, [])


def test_base_domain() -> None:
    assert base_domain("https://www.a.b.co.uk/x") == "b.co.uk"
    assert base_domain("api.mangadex.org") == "mangadex.org"
    assert base_domain("https://mangadot.net") == "mangadot.net"
    assert base_domain("localhost") == "localhost"


def test_candidate_json_round_trip(tmp_path: Path) -> None:
    cands = catalog.merge(parse_keiyoushi(fixture_bytes("keiyoushi_index.pb")), [])
    catalog.save(tmp_path / "c.json", cands)
    assert catalog.load(tmp_path / "c.json") == cands
    assert Availability.from_json(None) == Availability()
    minimal = Candidate.from_json(
        {"id": "x", "name": "x", "lang": "en", "origin": "plugin", "base_url": "u"}
    )
    assert minimal.catalogs == ()


def test_fetch_candidates(tmp_path: Path) -> None:
    clock, t = FakeClock(), FakeTransport()
    t.add(catalog.KEIYOUSHI_INDEX, resp(200, fixture_bytes("keiyoushi_index.pb")))
    t.add(catalog.MANGAYOMI_INDEX, resp(200, fixture_bytes("mangayomi_index.json")))
    client = PoliteClient(t, HostGate(None, 2.0, clock), clock, None, "ua")
    cands, skipped = catalog.fetch_candidates(client)
    assert len(cands) > 3
    assert skipped
    t2 = FakeTransport()
    t2.add("https://", resp(500, "down"))
    with pytest.raises(RuntimeError, match="HTTP 500"):
        catalog.fetch_candidates(
            PoliteClient(t2, HostGate(None, 2.0, clock), clock, None, "ua")
        )
    assert Request("GET", "x").timeout == 15.0
