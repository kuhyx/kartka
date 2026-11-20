# Copyright (c) 2026 Krzysztof Rudnicki
"""Rating counts Japanese manga only (kuhy, 2026-11-20).

The reference holds AniList's ``countryOfOrigin`` per title. Manhwa (``KR``),
manhua (``CN``/``TW``) and titles of unknown country (``None``/``""``: not
fetched, or not on AniList) are left out of every run sample and dropped
from a stored run's sample when it is re-reported.
"""

from __future__ import annotations

from dataclasses import replace
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterable

    from source_eval.models import RefTitle
    from source_eval.state import Manifest

#: AniList's ``countryOfOrigin`` of Japanese manga.
JAPAN = "JP"


def japanese(titles: Iterable[RefTitle]) -> list[str]:
    """Keys of the Japanese titles, in reference order."""
    return [t.key for t in titles if t.country == JAPAN]


def jp_manifest(manifest: Manifest, titles: Iterable[RefTitle]) -> Manifest:
    """``manifest`` with only its Japanese sample titles (order kept)."""
    keep = set(japanese(titles))
    return replace(manifest, sample=[k for k in manifest.sample if k in keep])
