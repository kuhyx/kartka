# Copyright (c) 2026 Krzysztof Rudnicki
"""Per-host pacing: request starts to one host stay ``interval`` s apart."""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING

from source_eval.budget import BudgetExhausted
from source_eval.fsio import read_json, write_json_atomic

if TYPE_CHECKING:
    from pathlib import Path

    from source_eval.http import Clock


def take(
    lock: threading.Lock | threading.Semaphore, latest: float | None, clock: Clock
) -> None:
    """Acquire ``lock``, giving up (:class:`BudgetExhausted`) at ``latest``."""
    if latest is None:  # (a Semaphore reads timeout=-1 as "do not wait")
        lock.acquire()
    elif not lock.acquire(timeout=max(0.0, latest - clock.now())):
        raise BudgetExhausted


class HostGate:
    """Spaces request starts to the same host at least ``interval`` s apart.

    The last-start times persist at ``path`` (at most every ``flush_every``
    seconds, plus :meth:`flush` at the end of a command): a later process
    keeps the spacing. Between budgeted batches that holds even without a
    flush, since a batch's last start is ``min_start`` + grace before its end.
    """

    def __init__(
        self,
        path: Path | None,
        interval: float,
        clock: Clock,
        *,
        flush_every: float = 1.0,
    ) -> None:
        """Load the last-request times persisted at ``path`` (if any)."""
        self._path = path
        self._interval = interval
        self._clock = clock
        self._flush_every = flush_every
        loaded = read_json(path, {}) if path is not None else {}
        self._last: dict[str, float] = dict(loaded) if isinstance(loaded, dict) else {}
        self._lock = threading.Lock()
        self._host_locks: dict[str, threading.Lock] = {}
        self._flushed = float("-inf")

    def wait(
        self,
        host: str,
        latest: float | None = None,
        inflight: threading.Semaphore | None = None,
    ) -> None:
        """Block until ``host`` may be contacted, then claim the slot.

        With ``latest``, a slot that would start after it is refused
        (:class:`BudgetExhausted`) without sleeping for it or claiming it.
        ``inflight`` is acquired (and left held for the caller) under the
        host's lock right before the claim, so the claim is the request's
        real start even when it had to wait for a free in-flight slot.
        """
        with self._lock:
            host_lock = self._host_locks.setdefault(host, threading.Lock())
        take(host_lock, latest, self._clock)
        try:
            slot = self._last.get(host, float("-inf")) + self._interval
            if latest is not None and slot > latest:
                raise BudgetExhausted
            if (delay := slot - self._clock.now()) > 0:
                self._clock.sleep(delay)
            if inflight is not None:
                take(inflight, latest, self._clock)
            with self._lock:
                self._last[host] = self._clock.now()
                if self._clock.now() - self._flushed >= self._flush_every:
                    self._save()
        finally:
            host_lock.release()

    def _save(self) -> None:
        if self._path is not None:
            write_json_atomic(self._path, self._last)
        self._flushed = self._clock.now()

    def flush(self) -> None:
        """Persist the last-start times now."""
        with self._lock:
            self._save()
