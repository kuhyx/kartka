# Copyright (c) 2026 Krzysztof Rudnicki
"""The one interface every probe backend implements."""

from __future__ import annotations

from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from source_eval.models import Candidate, Chapter, Hit, PageImage


class Backend(Protocol):
    """Reads one source the way Kartka would.

    Every method raises :class:`~source_eval.models.SourceError` on failure,
    with ``kind`` set when the failure was a challenge (cloudflare, captcha,
    403, 429, webview). Backends never try to get past a challenge.
    """

    def prepare(self, cand: Candidate) -> None:
        """Make ``cand`` usable (e.g. install its extension)."""
        ...

    def popular(self, cand: Candidate) -> list[Hit]:
        """First page of the popular listing: the cheap uptime probe."""
        ...

    def search(self, cand: Candidate, query: str) -> list[Hit]:
        """First page of search results for ``query``."""
        ...

    def chapters(self, cand: Candidate, hit: Hit) -> list[Chapter]:
        """Every chapter the source lists for ``hit``."""
        ...

    def pages(self, cand: Candidate, chapter: Chapter) -> list[PageImage]:
        """Page images of ``chapter``, in reading order."""
        ...

    def image(self, cand: Candidate, page: PageImage) -> bytes:
        """Raw bytes of one page image."""
        ...
