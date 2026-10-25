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


#: Order of the ``skipped`` groups (index, then reason).
_ORDER = {"keiyoushi": 0, "mangayomi": 1, "sy-backup": 2}
_ORDER |= {"language": 0, "dart": 1, "domain-overlap": 2, "duplicate": 3}

Skipped = list[dict[str, object]]


def _group(drops: list[tuple[str, str, str]]) -> Skipped:
    """``[(index, reason, name)]`` -> sorted ``{index, reason, count, names}``."""
    groups: dict[tuple[str, str], list[str]] = {}
    for index, reason, name in drops:
        groups.setdefault((index, reason), []).append(name)
    ordered = sorted(
        groups.items(),
        key=lambda kv: (_ORDER.get(kv[0][0], 99), _ORDER[kv[0][1]], kv[0][0]),
    )
    return [
        {"index": i, "reason": r, "count": len(n), "names": sorted(n)}
        for (i, r), n in ordered
    ]


def _drop_reason(
    entry: MangayomiEntry,
    covered: set[str],
    have: dict[tuple[str, str], Candidate],
) -> str | None:
    """Why a Mangayomi entry is not a candidate (first reason wins), or None."""
    domain = base_domain(entry.base_url)
    if entry.lang not in KEEP_LANGS:
        return "language"
    if not entry.js:
        return "dart"
    if domain in covered:
        return "domain-overlap"
    return "duplicate" if (domain, entry.lang) in have else None


def _plugins(
    mangayomi: list[MangayomiEntry],
    covered: set[str],
    drops: list[tuple[str, str, str]],
) -> list[Candidate]:
    """Mangayomi JS sources on domains nothing else covers; the rest dropped."""
    plugins: dict[tuple[str, str], Candidate] = {}
    for entry in mangayomi:
        domain = base_domain(entry.base_url)
        reason = _drop_reason(entry, covered, plugins)
        if reason is not None:
            drops.append(("mangayomi", reason, entry.name))
            continue
        plugins[domain, entry.lang] = Candidate(
            id=f"plugin:mangayomi-{entry.id}",
            name=entry.name,
            lang=entry.lang,
            origin="plugin",
            base_url=entry.base_url,
            catalogs=("mangayomi",),
        )
    return list(plugins.values())


def merge_report(
    keiyoushi: list[Candidate],
    mangayomi: list[MangayomiEntry],
    legacy: list[Candidate] | None = None,
) -> tuple[list[Candidate], Skipped]:
    """Native first, then Keiyoushi, then JS-only Mangayomi sites, then legacy.

    Only :data:`KEEP_LANGS` sources are candidates. A Mangayomi JS source on a
    domain Keiyoushi (or a native source) already covers is the same site, so
    it is measured once and only shows up in ``availability``. Dart Mangayomi
    sources cannot run in Kartka at all. Every dropped entry is returned,
    grouped by index and reason (each entry gets exactly one reason).
    """
    drops: list[tuple[str, str, str]] = []
    kept_kei = []
    for cand in keiyoushi:
        if cand.lang in KEEP_LANGS:
            kept_kei.append(cand)
        else:
            drops.append(("keiyoushi", "language", cand.name))
    kei = {base_domain(c.base_url) for c in kept_kei}
    js = {base_domain(e.base_url) for e in mangayomi if e.js}
    plugins = _plugins(mangayomi, kei | NATIVE_DOMAINS, drops)
    seen: set[str] = set()
    out: list[Candidate] = []
    for cand in [NATIVE_MANGADEX, *kept_kei, *plugins, *(legacy or [])]:
        if cand.id in seen:
            drops.append((cand.catalogs[0], "duplicate", cand.name))
            continue
        seen.add(cand.id)
        domain = base_domain(cand.base_url)
        avail = Availability(domain in NATIVE_DOMAINS, domain in js, domain in kei)
        out.append(replace(cand, availability=avail))
    return out, _group(drops)


def merge(
    keiyoushi: list[Candidate],
    mangayomi: list[MangayomiEntry],
    legacy: list[Candidate] | None = None,
) -> list[Candidate]:
    """The candidates of :func:`merge_report`, without the skipped groups."""
    return merge_report(keiyoushi, mangayomi, legacy)[0]


def _get(client: PoliteClient, url: str) -> bytes:
    response = client.fetch(Request("GET", url), cacheable=True)
    if response.status != _OK:
        msg = f"{url}: HTTP {response.status}"
        raise RuntimeError(msg)
    return response.body


def fetch_candidates(
    client: PoliteClient, legacy_path: Path | None = None
) -> tuple[list[Candidate], Skipped]:
    """Download both indexes and merge them (plus the legacy list, if given)."""
    keiyoushi = parse_keiyoushi(_get(client, KEIYOUSHI_INDEX))
    mangayomi = parse_mangayomi(json.loads(_get(client, MANGAYOMI_INDEX)))
    legacy = parse_legacy(read_json(legacy_path, [])) if legacy_path is not None else []
    return merge_report(keiyoushi, mangayomi, legacy)


def save(path: Path, candidates: list[Candidate]) -> None:
    """Write the candidate list."""
    write_json_atomic(path, [c.to_json() for c in candidates])


def load(path: Path) -> list[Candidate]:
    """Read a candidate list written by :func:`save`."""
    data = read_json(path, [])
    return [Candidate.from_json(d) for d in cast("list[dict[str, object]]", data)]


def save_skipped(path: Path, skipped: Skipped) -> None:
    """Write the entries the merge dropped (the run meta's ``skipped``)."""
    write_json_atomic(path, skipped)


def load_skipped(path: Path) -> Skipped:
    """Read :func:`save_skipped`'s file; ``[]`` before the first refresh."""
    return cast("Skipped", read_json(path, []))
