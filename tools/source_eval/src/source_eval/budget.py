# Copyright (c) 2026 Krzysztof Rudnicki
"""Time budgets: every command stops cleanly and resumes on the next call."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from source_eval.http import Clock


class Deadline:
    """Expires ``seconds`` after creation; ``None`` never expires."""

    def __init__(self, clock: Clock, seconds: float | None) -> None:
        """Start the budget now."""
        self._clock = clock
        self._until = None if seconds is None else clock.now() + seconds

    def expired(self) -> bool:
        """True once the budget is spent."""
        return self._until is not None and self._clock.now() >= self._until


def stratified(items: list[str], n: int | None) -> list[str]:
    """``n`` evenly spaced items (order kept); all of them when ``n`` is None.

    Every source is measured against the same deterministic sample, which is
    what makes coverage and subset comparisons meaningful.
    """
    if n is None or n >= len(items):
        return list(items)
    if n <= 0:
        return []
    return [items[(i * len(items)) // n] for i in range(n)]
