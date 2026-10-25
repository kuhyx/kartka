# Copyright (c) 2026 Krzysztof Rudnicki
"""The weekly units: 500 titles, Sunday 19:00 (kuhy, 2026-10-25).

500 runs >= 2 h, so the ramp would walk it back; the unit pins the sample
instead. Allowed because 500 extrapolates to ~4 h, under kuhy's 24 h bound.
"""

from __future__ import annotations

from pathlib import Path

SYSTEMD = Path(__file__).resolve().parents[1] / "systemd"


def _lines(unit: str) -> list[str]:
    return (SYSTEMD / unit).read_text().splitlines()


def test_full_run_starts_sunday_evening() -> None:
    timer = _lines("kartka-source-eval-full.timer")
    assert "OnCalendar=Sun *-*-* 19:00:00" in timer
    assert "Persistent=true" in timer


def test_full_run_pins_the_500_title_sample() -> None:
    service = _lines("kartka-source-eval-full.service")
    assert "Environment=KARTKA_EVAL_SAMPLE=500" in service
