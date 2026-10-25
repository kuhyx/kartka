# Copyright (c) 2026 Krzysztof Rudnicki
"""The search queries a source is asked for one reference title."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterable

    from source_eval.models import RefTitle


def _distinct(titles: Iterable[str]) -> list[str]:
    """Titles in order, dropping ones that differ from an earlier only by case/spacing.

    A source search is case-insensitive, so ``ONE PIECE`` after ``One Piece``
    would cost the server a second fetch that cannot answer differently.
    Punctuation is kept: ``Re:Zero`` and ``Re Zero`` can search differently.
    """
    seen: dict[str, str] = {}
    for title in titles:
        seen.setdefault(" ".join(title.casefold().split()), title)
    return list(seen.values())


def queries(ref: RefTitle, lang: str) -> list[str]:
    """Two search queries: the main title and the first alt title.

    A Japanese source is searched by the native title first, then the first
    other title. A title that only repeats the first by case or spacing is
    not searched again.
    """
    if lang == "ja" and ref.native:
        return _distinct((ref.native, *ref.titles))[:2]
    return _distinct(ref.titles[:2])
