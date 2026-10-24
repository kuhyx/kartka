# Copyright (c) 2026 Krzysztof Rudnicki
"""Value types shared by every stage of the evaluator."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Literal, cast
from urllib.parse import urlsplit

Origin = Literal["native", "suwayomi", "plugin"]
_SHORT_SLD = frozenset({"co", "com", "net", "org", "ac", "or", "ne", "go"})
_CC_TLD_LEN = 2


def base_domain(url_or_host: str) -> str:
    """Registrable domain, e.g. ``https://www.a.b.co.uk/x`` -> ``b.co.uk``.

    A small heuristic instead of the public-suffix list: keep two labels, or
    three when the second-level label is a generic one under a ccTLD.
    """
    host = urlsplit(url_or_host).hostname if "//" in url_or_host else url_or_host
    labels = (host or url_or_host).lower().strip(".").split(".")
    keep = 3 if len(labels) > 2 and len(labels[-1]) == _CC_TLD_LEN and labels[-2] in _SHORT_SLD else 2  # noqa: PLR2004
    return ".".join(labels[-keep:])


@dataclass(frozen=True, slots=True)
class Availability:
    """Which Kartka backends can read this site at all (contract §5)."""

    native: bool = False
    mangayomi_js: bool = False
    keiyoushi: bool = False

    def to_json(self) -> dict[str, bool]:
        """Contract field names."""
        return {"native": self.native, "mangayomiJs": self.mangayomi_js, "keiyoushi": self.keiyoushi}

    @classmethod
    def from_json(cls, data: object) -> Availability:
        """Inverse of :meth:`to_json`; anything else means unknown (all false)."""
        if not isinstance(data, dict):
            return cls()
        return cls(bool(data.get("native")), bool(data.get("mangayomiJs")), bool(data.get("keiyoushi")))


@dataclass(frozen=True, slots=True)
class Candidate:
    """One source that may be worth keeping.

    ``id`` follows the contract: ``mangadex``, ``suwayomi:<tachiyomiId>`` or
    ``plugin:<pluginId>``.
    """

    id: str
    name: str
    lang: str
    origin: Origin
    base_url: str
    pkg: str = ""
    catalogs: tuple[str, ...] = ()
    installed: bool = False
    availability: Availability = Availability()

    @property
    def host(self) -> str:
        """Upstream host: the key requests are paced by."""
        return (urlsplit(self.base_url).hostname or self.base_url).removeprefix("www.")

    def to_json(self) -> dict[str, object]:
        """JSON-ready dict."""
        out = asdict(self)
        out["catalogs"] = list(self.catalogs)
        out["availability"] = self.availability.to_json()
        return out

    @classmethod
    def from_json(cls, data: dict[str, object]) -> Candidate:
        """Inverse of :meth:`to_json`."""
        return cls(
            id=str(data["id"]),
            name=str(data["name"]),
            lang=str(data["lang"]),
            origin=cast("Origin", data["origin"]),
            base_url=str(data["base_url"]),
            pkg=str(data.get("pkg", "")),
            catalogs=tuple(cast("list[str]", data.get("catalogs", []))),
            installed=bool(data.get("installed", False)),
            availability=Availability.from_json(data.get("availability")),
        )


@dataclass(frozen=True, slots=True)
class RefTitle:
    """One title of the reference set, with every name it is known by."""

    key: str
    titles: tuple[str, ...]
    chapters: int | None = None
    chapters_from: str | None = None
    anilist_id: int | None = None
    origins: tuple[str, ...] = ()

    def to_json(self) -> dict[str, object]:
        """JSON-ready dict."""
        return {
            "key": self.key,
            "titles": list(self.titles),
            "chapters": self.chapters,
            "chaptersFrom": self.chapters_from,
            "anilistId": self.anilist_id,
            "origins": list(self.origins),
        }

    @classmethod
    def from_json(cls, data: dict[str, object]) -> RefTitle:
        """Inverse of :meth:`to_json`."""
        chapters = data.get("chapters")
        anilist = data.get("anilistId")
        return cls(
            key=str(data["key"]),
            titles=tuple(cast("list[str]", data["titles"])),
            chapters=int(cast("int", chapters)) if chapters is not None else None,
            chapters_from=cast("str | None", data.get("chaptersFrom")),
            anilist_id=int(cast("int", anilist)) if anilist is not None else None,
            origins=tuple(cast("list[str]", data.get("origins", []))),
        )


@dataclass(frozen=True, slots=True)
class Hit:
    """A search result: what the source calls it and how to open it."""

    title: str
    ref: str


@dataclass(frozen=True, slots=True)
class Chapter:
    """A chapter as listed by the source."""

    ref: str
    number: float | None


@dataclass(frozen=True, slots=True)
class PageImage:
    """A page image URL plus any headers the source needs."""

    url: str
    headers: dict[str, str] = field(default_factory=dict)


class SourceError(Exception):
    """A source operation failed; ``kind`` is set when it was a challenge."""

    def __init__(self, message: str, kind: str | None = None) -> None:
        """Record ``message`` and the challenge ``kind`` (if any)."""
        super().__init__(message)
        self.kind = kind
