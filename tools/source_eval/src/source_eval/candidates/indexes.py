# Copyright (c) 2026 Krzysztof Rudnicki
"""Parse the Keiyoushi (protobuf) and Mangayomi (JSON) extension indexes."""

from __future__ import annotations

from dataclasses import dataclass
import gzip
from typing import cast

from source_eval import protowire as pw
from source_eval.models import Candidate

KEEP_LANGS = frozenset({"en", "all"})
#: kuhy's installed SY set, matched as package suffixes.
INSTALLED_PKGS = (
    "all.mangadex",
    "en.allanime",
    "all.hdoujin",
    "en.explosm",
    "en.gwtb",
    "en.mangadotnet",
)
# Field numbers of Mihon's extension-repo proto, verified against Suwayomi's
# decoding of the same file (MangaDex en == 2499283573021220255).
_ROOT_EXTENSIONS, _EXT_ITEM = 101, 1
_EXT_NAME, _EXT_PKG, _EXT_SOURCE = 1, 2, 8
_SRC_ID, _SRC_NAME, _SRC_LANG, _SRC_BASE = 1, 2, 3, 4
_GZIP_MAGIC = b"\x1f\x8b"
_MANGAYOMI_JS = 1  # sourceCodeLanguage: 0 = Dart, 1 = JavaScript


@dataclass(frozen=True, slots=True)
class MangayomiEntry:
    """One Mangayomi source. Only JS ones can run in Kartka's plugin host."""

    id: str
    name: str
    lang: str
    base_url: str
    js: bool


def is_installed(pkg: str) -> bool:
    """True when ``pkg`` is one of kuhy's installed extensions."""
    return pkg.endswith(INSTALLED_PKGS)


def parse_keiyoushi(blob: bytes) -> list[Candidate]:
    """Every English or multi-language source in a Keiyoushi ``index.pb``."""
    raw = gzip.decompress(blob) if blob.startswith(_GZIP_MAGIC) else blob
    root = pw.group(raw)
    out: list[Candidate] = []
    for container in root.get(_ROOT_EXTENSIONS, []):
        for ext_blob in pw.group(cast("bytes", container)).get(_EXT_ITEM, []):
            ext = pw.group(cast("bytes", ext_blob))
            pkg = pw.text(ext, _EXT_PKG)
            for src_blob in ext.get(_EXT_SOURCE, []):
                src = pw.group(cast("bytes", src_blob))
                lang = pw.text(src, _SRC_LANG)
                if lang not in KEEP_LANGS:
                    continue
                out.append(
                    Candidate(
                        id=f"suwayomi:{pw.integer(src, _SRC_ID)}",
                        name=pw.text(src, _SRC_NAME) or pw.text(ext, _EXT_NAME),
                        lang=lang,
                        origin="suwayomi",
                        base_url=pw.text(src, _SRC_BASE),
                        pkg=pkg,
                        catalogs=("keiyoushi",),
                        installed=is_installed(pkg),
                    )
                )
    return out


def parse_mangayomi(data: object) -> list[MangayomiEntry]:
    """Every manga source in a Mangayomi index (all languages, Dart and JS)."""
    if not isinstance(data, list):
        msg = "mangayomi index is not a list"
        raise TypeError(msg)
    return [
        MangayomiEntry(
            id=str(item["id"]),
            name=str(item["name"]),
            lang=str(item.get("lang", "")),
            base_url=str(item.get("baseUrl", "")),
            js=item.get("sourceCodeLanguage") == _MANGAYOMI_JS,
        )
        for item in cast("list[dict[str, object]]", data)
        if item.get("isManga") is not False
    ]
