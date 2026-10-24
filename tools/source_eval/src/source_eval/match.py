# Copyright (c) 2026 Krzysztof Rudnicki
"""Fuzzy title matching: does a source's title name this reference title?"""

from __future__ import annotations

from typing import TYPE_CHECKING
import unicodedata
lazy from collections.abc import Iterable

from rapidfuzz import fuzz

if TYPE_CHECKING:
    from source_eval.models import Hit, RefTitle

#: Minimum similarity (0..1) to count a hit as the same title. Strict on
#: purpose: "Berserk" must not match "Berserk of Gluttony".
THRESHOLD = 0.9


def normalize(title: str) -> str:
    """Case-, accent- and punctuation-insensitive form of ``title``."""
    decomposed = unicodedata.normalize("NFKD", title.replace("&", " and "))
    kept = "".join(
        ch if ch.isalnum() else " "
        for ch in decomposed
        if not unicodedata.combining(ch)
    )
    words = kept.casefold().split()
    if words[:1] == ["the"]:
        words = words[1:]
    return " ".join(words)


def similarity(a: str, b: str) -> float:
    """Similarity of two titles in ``[0, 1]`` after normalisation."""
    na, nb = normalize(a), normalize(b)
    if not na or not nb:
        return 0.0
    return float(fuzz.ratio(na, nb)) / 100.0


def title_score(title: str, names: Iterable[str]) -> float:
    """Best similarity of ``title`` against any of ``names``."""
    return max((similarity(title, n) for n in names), default=0.0)


def best_hit(hits: Iterable[Hit], ref: RefTitle) -> Hit | None:
    """The hit that best matches ``ref`` (any alt title), if good enough."""
    best: Hit | None = None
    best_score = THRESHOLD
    for hit in hits:
        score = title_score(hit.title, ref.titles)
        if score >= best_score:
            best, best_score = hit, score + 1e-9
    return best
