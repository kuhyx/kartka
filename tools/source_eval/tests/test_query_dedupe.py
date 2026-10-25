# Copyright (c) 2026 Krzysztof Rudnicki
"""A second search that differs only by case or spacing is wasted server work."""

from __future__ import annotations

from source_eval.models import RefTitle
from source_eval.queries import queries


def test_alt_title_differing_only_by_case_is_not_searched_again() -> None:
    ref = RefTitle("anilist:1", ("One Piece", "ONE PIECE"), anilist_id=1)
    assert queries(ref, "en") == ["One Piece"]


def test_alt_title_differing_only_by_spacing_is_not_searched_again() -> None:
    ref = RefTitle("anilist:2", ("Solo  Leveling", "solo leveling "), anilist_id=2)
    assert queries(ref, "all") == ["Solo  Leveling"]


def test_native_and_a_case_variant_of_it_search_once_then_the_next_title() -> None:
    ref = RefTitle("anilist:3", ("ABC", "abc", "Other"), anilist_id=3, native="Abc")
    assert queries(ref, "ja") == ["Abc", "Other"]


def test_punctuation_still_makes_a_distinct_query() -> None:
    ref = RefTitle("anilist:4", ("Re:Zero", "Re Zero"), anilist_id=4)
    assert queries(ref, "en") == ["Re:Zero", "Re Zero"]
