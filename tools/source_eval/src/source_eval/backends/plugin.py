# Copyright (c) 2026 Krzysztof Rudnicki
"""Kartka JS plugins (incl. converted Mangayomi JS): interface stub.

The plugin runtime lives in the Dart app (``lib/plugins/runtime/``). Until a
headless host exists, plugin candidates get uptime probes only and stay
``pending``. Implementing this class is the whole integration.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, NoReturn

from source_eval.models import SourceError

if TYPE_CHECKING:
    from source_eval.models import Candidate, Chapter, Hit, PageImage

NOT_AVAILABLE = "no headless plugin runtime yet"


class PluginBackend:
    """Raises on every call; the evaluator treats this as 'not measured'."""

    def _unavailable(self) -> NoReturn:
        raise SourceError(NOT_AVAILABLE)

    def prepare(self, cand: Candidate) -> None:
        """Not available yet."""
        del cand
        self._unavailable()

    def popular(self, cand: Candidate) -> list[Hit]:
        """Not available yet."""
        del cand
        self._unavailable()

    def search(self, cand: Candidate, query: str) -> list[Hit]:
        """Not available yet."""
        del cand, query
        self._unavailable()

    def chapters(self, cand: Candidate, hit: Hit) -> list[Chapter]:
        """Not available yet."""
        del cand, hit
        self._unavailable()

    def pages(self, cand: Candidate, chapter: Chapter) -> list[PageImage]:
        """Not available yet."""
        del cand, chapter
        self._unavailable()

    def image(self, cand: Candidate, page: PageImage) -> bytes:
        """Not available yet."""
        del cand, page
        self._unavailable()
