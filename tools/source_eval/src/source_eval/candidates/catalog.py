# Copyright (c) 2026 Krzysztof Rudnicki
"""Merge every index into one de-duplicated candidate list."""

from __future__ import annotations

from dataclasses import replace
import json
from typing import cast
lazy from pathlib import Path

from source_eval.candidates.indexes import (
    KEEP_LANGS,
    MangayomiEntry,
    parse_keiyoushi,
    parse_mangayomi,
)
from source_eval.fsio import read_json, write_json_atomic
from source_eval.http import Request
from source_eval.models import Availability, Candidate, base_domain
lazy from source_eval.polite import PoliteClient

KEIYOUSHI_INDEX = "https://github.com/keiyoushi/extensions/raw/repo/index.pb"
MANGAYOMI_INDEX = "https://kodjodevf.github.io/mangayomi-extensions/index.json"
_OK = 200

#: Sites a Kartka-native Dart source reads (today only MangaDex).
NATIVE_DOMAINS = frozenset({"mangadex.org"})
NATIVE_MANGADEX = Candidate(
    id="mangadex",
    name="MangaDex",
    lang="en",
    origin="native",
    base_url="https://mangadex.org",
    catalogs=("native",),
    installed=True,
)


def parse_legacy(data: object) -> list[Candidate]:
    """Kuhy's SY-backup sources that no current index carries (hand-identified)."""
    return [
        Candidate(
            id=f"plugin:legacy-{item['slug']}",
            name=str(item["name"]),
            lang=str(item["lang"]),
            origin="plugin",
            base_url=str(item["baseUrl"]),
            catalogs=("sy-backup",),
            installed=True,
        )
        for item in cast("list[dict[str, object]]", data)
    ]


def merge(
    keiyoushi: list[Candidate],
    mangayomi: list[MangayomiEntry],
    legacy: list[Candidate] | None = None,
) -> list[Candidate]:
    """Native first, then Keiyoushi, then JS-only Mangayomi sites.

    A Mangayomi JS source on a domain Keiyoushi already covers is the same
    site, so it is measured once (through Suwayomi) and only shows up in
    ``availability``. Dart Mangayomi sources cannot run in Kartka at all and
    are not candidates.
    """
    kei = {base_domain(c.base_url) for c in keiyoushi}
    js = {base_domain(e.base_url) for e in mangayomi if e.js}
    plugins: dict[tuple[str, str], Candidate] = {}
    for entry in mangayomi:
        domain = base_domain(entry.base_url)
        if entry.js and entry.lang in KEEP_LANGS and domain not in kei | NATIVE_DOMAINS:
            plugins.setdefault(
                (domain, entry.lang),
                Candidate(
                    id=f"plugin:mangayomi-{entry.id}",
                    name=entry.name,
                    lang=entry.lang,
                    origin="plugin",
                    base_url=entry.base_url,
                    catalogs=("mangayomi",),
                ),
            )
    seen: set[str] = set()
    out: list[Candidate] = []
    for cand in [NATIVE_MANGADEX, *keiyoushi, *plugins.values(), *(legacy or [])]:
        if cand.id in seen:
            continue
        seen.add(cand.id)
        domain = base_domain(cand.base_url)
        avail = Availability(domain in NATIVE_DOMAINS, domain in js, domain in kei)
        out.append(replace(cand, availability=avail))
    return out


def _get(client: PoliteClient, url: str) -> bytes:
    response = client.fetch(Request("GET", url), cacheable=True)
    if response.status != _OK:
        msg = f"{url}: HTTP {response.status}"
        raise RuntimeError(msg)
    return response.body


def fetch_candidates(
    client: PoliteClient, legacy_path: Path | None = None
) -> list[Candidate]:
    """Download both indexes and merge them (plus the legacy list, if given)."""
    keiyoushi = parse_keiyoushi(_get(client, KEIYOUSHI_INDEX))
    mangayomi = parse_mangayomi(json.loads(_get(client, MANGAYOMI_INDEX)))
    legacy = parse_legacy(read_json(legacy_path, [])) if legacy_path is not None else []
    return merge(keiyoushi, mangayomi, legacy)


def save(path: Path, candidates: list[Candidate]) -> None:
    """Write the candidate list."""
    write_json_atomic(path, [c.to_json() for c in candidates])


def load(path: Path) -> list[Candidate]:
    """Read a candidate list written by :func:`save`."""
    data = read_json(path, [])
    return [Candidate.from_json(d) for d in cast("list[dict[str, object]]", data)]
