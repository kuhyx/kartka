# Copyright (c) 2026 Krzysztof Rudnicki
"""Build ``data/reference.json``: AniList top N + kuhy's SY library titles.

Resumable: progress lives in the output file itself, so a budget-limited
call picks up where the last one stopped.
"""

from __future__ import annotations

from dataclasses import replace
from typing import TYPE_CHECKING, cast

from source_eval.fsio import read_json, write_json_atomic
from source_eval.match import normalize
from source_eval.models import RefTitle
from source_eval.reference import anilist, mangaupdates

if TYPE_CHECKING:
    from pathlib import Path

    from source_eval.budget import Deadline
    from source_eval.http import Clock
    from source_eval.polite import PoliteClient


#: Cursor of the Japan-only top list. An older unfiltered build's
#: ``anilistPage`` is left as it was: its titles stay, the JP pages top up.
JP_PAGE = "anilistJpPage"


class Reference:
    """The reference file plus its resume cursor."""

    def __init__(self, path: Path, clock: Clock) -> None:
        """Load ``path`` (or start empty)."""
        self.path = path
        self._clock = clock
        data = cast("dict[str, object]", read_json(path, {}))
        self.progress = cast("dict[str, int]", data.get("progress", {JP_PAGE: 0}))
        # SY titles by normalised name, not list position: a newer backup can
        # reorder or insert titles and an index cursor would skip some.
        self.sy_done = set(cast("list[str]", data.get("syProcessed", [])))
        self.complete = bool(data.get("complete", False))
        raw = cast("list[dict[str, object]]", data.get("titles", []))
        self.titles = [RefTitle.from_json(t) for t in raw]

    def save(self) -> None:
        """Persist titles and cursor atomically."""
        write_json_atomic(
            self.path,
            {
                "generatedAt": self._clock.now(),
                "complete": self.complete,
                "progress": self.progress,
                "syProcessed": sorted(self.sy_done),
                "referenceSize": len(self.titles),
                "titles": [t.to_json() for t in self.titles],
            },
        )

    def add(self, ref: RefTitle) -> None:
        """Append ``ref``, or merge its origins into the existing entry."""
        for i, have in enumerate(self.titles):
            if have.key == ref.key:
                origins = tuple(dict.fromkeys((*have.origins, *ref.origins)))
                self.titles[i] = replace(have, origins=origins)
                return
        self.titles.append(ref)


def load_sy_titles(path: Path) -> list[str]:
    """Titles from a plain JSON list (strings or ``{"title": ...}``), if present."""
    data = read_json(path, [])
    out: list[str] = []
    for item in cast("list[object]", data):
        title = item.get("title") if isinstance(item, dict) else item
        if isinstance(title, str) and title.strip():
            out.append(title.strip())
    return out


def build(  # noqa: PLR0913 -- explicit knobs beat a config object here
    client: PoliteClient,
    ref: Reference,
    sy_titles: list[str],
    deadline: Deadline,
    *,
    top: int = 500,
    per_page: int = 50,
    batch: int = 50,
) -> bool:
    """Advance the build; True once every step is done.

    Never short-circuits on ``complete``: SY titles added after the AniList
    part finished (a new ``sy_titles.json``) are still picked up, and titles
    stored before native titles or countries existed are backfilled
    ``batch`` at a time.
    """
    while ref.progress.get(JP_PAGE, 0) * per_page < top:
        if deadline.expired():
            return False
        page = ref.progress.get(JP_PAGE, 0) + 1
        titles, has_next = anilist.top_page(client, page, per_page)
        for entry in titles[: top - (page - 1) * per_page]:
            ref.add(entry)
        ref.progress[JP_PAGE] = page if has_next else top
        ref.save()
    for title in sy_titles:
        if normalize(title) in ref.sy_done:
            continue
        if deadline.expired():
            return False
        found = anilist.search(client, title)
        ref.add(
            found
            or RefTitle(key=f"sy:{normalize(title)}", titles=(title,), origins=("sy",))
        )
        ref.sy_done.add(normalize(title))
        ref.save()
    if not _backfill_details(client, ref, deadline, batch):
        return False
    ref.complete = True
    ref.save()
    return True


def _backfill_details(
    client: PoliteClient, ref: Reference, deadline: Deadline, batch: int
) -> bool:
    """Fill ``native`` and ``country`` where unfetched; True when done.

    A title AniList does not return gets ``""`` for both, so it is not asked
    for again; a native title already stored is kept.
    """
    while todo := [
        i
        for i, t in enumerate(ref.titles)
        if t.anilist_id is not None and (t.native is None or t.country is None)
    ][:batch]:
        if deadline.expired():
            return False
        ids = [cast("int", ref.titles[i].anilist_id) for i in todo]
        found = anilist.details(client, ids)
        for i, aid in zip(todo, ids, strict=True):
            native, country = found.get(aid, ("", ""))
            have = ref.titles[i]
            ref.titles[i] = replace(
                have,
                native=native if have.native is None else have.native,
                country=country,
            )
        ref.save()
    return True


def enrich_chapters(
    client: PoliteClient, ref: Reference, keys: list[str] | None, deadline: Deadline
) -> bool:
    """Fill missing chapter counts from MangaUpdates; True when done."""
    wanted = set(keys) if keys is not None else None
    for i, title in enumerate(ref.titles):
        if title.chapters_from is not None or (
            wanted is not None and title.key not in wanted
        ):
            continue
        if deadline.expired():
            return False
        latest = mangaupdates.latest_chapter(client, title)
        source = "mangaupdates" if latest else "none"
        ref.titles[i] = replace(title, chapters=latest, chapters_from=source)
        ref.save()
    return True
