# Copyright (c) 2026 Krzysztof Rudnicki
"""Time budgets: every command stops cleanly and resumes on the next call.

A budget is a hard wall-clock promise (kuhy, 2026-10-25): an invocation with
``--budget 55`` ends within 55 s of its start *including* any request still
in flight. :class:`RequestBudget` enforces it per request: a request starts
only when its timeout fits in what is left, and a timeout shortened to fit
that is hit is the budget's doing (:class:`BudgetExhausted`), never the
source's failure.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

    from source_eval.http import Clock

#: Exit code when the budget ran out and another call should continue.
MORE_WORK = 10


class BudgetExhausted(Exception):  # noqa: N818 -- a stop signal, not an error
    """Not enough budget left to start (or finish) a request: stop, resume later.

    Deliberately not a ``SourceError``: nothing about the source was learned,
    so the step that hit it is dropped and redone by the next invocation.
    """


class Deadline:
    """Expires ``seconds`` after ``start`` (default: now); ``None`` never does."""

    def __init__(
        self, clock: Clock, seconds: float | None, *, start: float | None = None
    ) -> None:
        """Start the budget at ``start`` (e.g. process start) or now."""
        self._clock = clock
        begin = clock.now() if start is None else start
        self.until = None if seconds is None else begin + seconds

    def expired(self) -> bool:
        """True once the budget is spent."""
        return self.until is not None and self._clock.now() >= self.until

    def remaining(self) -> float:
        """Seconds left (``inf`` without a budget)."""
        return float("inf") if self.until is None else self.until - self._clock.now()


@dataclass(frozen=True, slots=True)
class RequestBudget:
    """Fits each request into a :class:`Deadline`.

    ``grace`` is kept back for the final checkpoint and exit; a request may
    start only while at least ``min_start`` seconds (or its whole timeout,
    when shorter) remain after it.
    """

    deadline: Deadline | None
    min_start: float = 5.0
    grace: float = 1.0

    def _left(self) -> float:
        if self.deadline is None:
            return float("inf")
        return self.deadline.remaining() - self.grace

    def latest_start(self) -> float | None:
        """Last moment a request may start (``None``: any time)."""
        if self.deadline is None or self.deadline.until is None:
            return None
        return self.deadline.until - self.grace - self.min_start

    def timeout(self, wanted: float) -> float:
        """``wanted``, shortened to fit; raises :class:`BudgetExhausted`."""
        allowed = min(wanted, self._left())
        if allowed < min(wanted, self.min_start):
            raise BudgetExhausted
        return allowed


def within(work: Callable[[], bool]) -> bool:
    """``work()``, or False when the budget stopped it (resume next call)."""
    try:
        return work()
    except BudgetExhausted:
        return False


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
