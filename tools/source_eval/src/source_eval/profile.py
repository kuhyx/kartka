# Copyright (c) 2026 Krzysztof Rudnicki
"""The scoring profile: user-tunable weights, keep bar and cut switches.

``DEFAULT`` is the evaluator's historic scoring and is immutable; it is the
one definition on the Python side (the app has its own in
``lib/source_health/scoring/profile.dart``, and
``tests/fixtures/scoring_profile.json`` pins the two together). The active
profile is the synced setting ``sourceHealth.scoring`` (contract §5).
"""

from __future__ import annotations

from dataclasses import dataclass, field
import math
from typing import Any

#: The synced-setting key (``lib/sync/settings/settings_catalog.dart``).
SETTING_KEY = "sourceHealth.scoring"
#: Its node relative to the app's e2e root: ``settings/<rtdbKey(key)>``
#: (``.`` escapes to ``~2E``); also the path its seal is bound to.
SETTING_REL = "settings/sourceHealth~2Escoring"
#: Where it lives in RTDB, sealed by the app (``source_eval.e2e``).
SETTING_NODE = f"kartka-e2e/{SETTING_REL}"

_WEIGHT_FIELDS = (
    ("completeCoverage", "complete_coverage"),
    ("uptime", "uptime"),
    ("imageQuality", "image_quality"),
    ("speed", "speed"),
)
#: Weights of profiles written before coverage and chapter completeness
#: merged (2026-10-25), with their old defaults: they add up to the merged one.
_LEGACY_WEIGHTS = (("coverage", 0.30), ("chapterCompleteness", 0.20))
# ``subset`` is no longer a switch (a graded penalty instead): ignored.
_CUT_FIELDS = (
    ("blocking", "blocking"),
    ("coverage", "coverage"),
    ("uptime", "uptime"),
    ("needsBrowserEngine", "needs_browser_engine"),
    ("pagesNeverLoad", "pages_never_load"),
)


@dataclass(frozen=True, slots=True)
class Weights:
    """Weights of the four score parts, each 0 to 1 (0 turns a part off).

    ``complete_coverage`` is the merged coverage (found with a complete
    chapter list), the old coverage .30 + chapter completeness .20.
    """

    complete_coverage: float = 0.50
    uptime: float = 0.20
    image_quality: float = 0.15
    speed: float = 0.15

    def values(self) -> list[float]:
        """The raw weights in contract order."""
        return [getattr(self, attr) for _, attr in _WEIGHT_FIELDS]

    def total(self) -> float:
        """Sum of the raw weights, added in order exactly as the app does."""
        total = 0.0
        for value in self.values():
            total += value
        return total

    def normalised(self) -> tuple[float, float, float, float]:
        """The weights scaled to sum 1, in contract order. Needs a non-zero sum."""
        total = self.total()
        c, u, q, s = (v / total for v in self.values())
        return c, u, q, s


@dataclass(frozen=True, slots=True)
class Cuts:
    """Per-reason switches: an enabled one cuts every source it applies to."""

    blocking: bool = False
    coverage: bool = False
    uptime: bool = False
    needs_browser_engine: bool = False
    pages_never_load: bool = False

    def enabled(self) -> frozenset[str]:
        """Wire names of the enabled switches."""
        return frozenset(name for name, attr in _CUT_FIELDS if getattr(self, attr))


@dataclass(frozen=True, slots=True)
class Profile:
    """Weights, pages-load multiplier, keep bar and cut switches."""

    weights: Weights = field(default_factory=Weights)
    pages_load_multiplier: bool = True
    keep_score: float = 0.90
    cuts: Cuts = field(default_factory=Cuts)

    @property
    def name(self) -> str:
        """``default`` when equal to :data:`DEFAULT` by value, else ``custom``."""
        return "default" if self == DEFAULT else "custom"

    def to_json(self) -> dict[str, Any]:
        """The wire form (without ``name``; the meta node adds it)."""
        return {
            "weights": {n: getattr(self.weights, a) for n, a in _WEIGHT_FIELDS},
            "pagesLoadMultiplier": self.pages_load_multiplier,
            "keepScore": self.keep_score,
            "cuts": {n: getattr(self.cuts, a) for n, a in _CUT_FIELDS},
        }


#: The evaluator's historic scoring. Never mutated; "reset" restores it.
DEFAULT = Profile()


def _number(value: object) -> float | None:
    """A finite number in [0, 1], else None (bools are not numbers here)."""
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    return float(value) if math.isfinite(value) and 0 <= value <= 1 else None


def _fields(raw: object, names: tuple[tuple[str, str], ...]) -> dict[str, Any] | None:
    """The present fields of ``raw`` as attribute kwargs; None if not an object."""
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        return None
    return {attr: raw[name] for name, attr in names if name in raw}


def _weights(raw: object) -> dict[str, float] | None:
    """Weight kwargs from the wire form; None when any is invalid.

    Without ``completeCoverage``, the legacy ``coverage`` and
    ``chapterCompleteness`` (each defaulting to its old value) add up to it;
    a sum above 1 scales every weight down by it, keeping their ratios.
    """
    fields = _fields(raw, _WEIGHT_FIELDS)
    if fields is None:
        return None
    parsed: dict[str, float] = {}
    for attr, value in fields.items():
        number = _number(value)
        if number is None:
            return None
        parsed[attr] = number
    if "complete_coverage" in parsed or not isinstance(raw, dict):
        return parsed
    merged = 0.0
    for name, old_default in _LEGACY_WEIGHTS:
        number = _number(raw.get(name, old_default))
        if number is None:
            return None
        merged += number
    if merged <= 1:
        return {**parsed, "complete_coverage": merged}
    full = {
        attr: parsed.get(attr, getattr(DEFAULT.weights, attr))
        for _, attr in _WEIGHT_FIELDS
    }
    full["complete_coverage"] = merged
    return {attr: value / merged for attr, value in full.items()}


def parse_profile(raw: object) -> Profile | None:
    """A profile from its wire form, or None when it is not valid.

    A missing field takes its DEFAULT; unknown keys are ignored. A field of
    the wrong type, a weight or ``keepScore`` outside 0..1 and weights that
    are all zero make the whole profile invalid (callers fall back to DEFAULT).
    Legacy weights merge (see :func:`_weights`); the old ``cuts.subset`` is
    ignored.
    """
    if not isinstance(raw, dict):
        return None
    parsed = _weights(raw.get("weights"))
    cuts = _fields(raw.get("cuts"), _CUT_FIELDS)
    if parsed is None or cuts is None:
        return None
    if not all(isinstance(value, bool) for value in cuts.values()):
        return None
    multiplier = raw.get("pagesLoadMultiplier", DEFAULT.pages_load_multiplier)
    keep = _number(raw.get("keepScore", DEFAULT.keep_score))
    if not isinstance(multiplier, bool) or keep is None:
        return None
    result = Profile(Weights(**parsed), multiplier, keep, Cuts(**cuts))
    return result if result.weights.total() > 0 else None
