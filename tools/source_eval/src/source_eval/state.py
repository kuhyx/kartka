# Copyright (c) 2026 Krzysztof Rudnicki
"""Per-run, per-source progress on disk; every step is a checkpoint."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
from typing import TYPE_CHECKING, cast

from source_eval.fsio import read_json, write_json_atomic

if TYPE_CHECKING:
    from pathlib import Path

    from source_eval.polite import Observation


def sha1(text: str) -> str:
    """Lower-case hex SHA-1 (the contract's RTDB-safe key)."""
    return hashlib.sha1(text.encode(), usedforsecurity=False).hexdigest()


@dataclass(frozen=True, slots=True)
class Manifest:
    """What every source in a run is measured against.

    ``completeness`` is legacy (chapter lists are fetched for every found
    title now). ``all_chapters`` marks a run made that way: only such a run
    publishes the merged coverage (``coverage.completeRatio``); older runs
    keep the old coverage.
    """

    sample: list[str]
    completeness: int
    images: int
    pages: int
    all_chapters: bool = False

    @classmethod
    def load(cls, path: Path) -> Manifest | None:
        """The manifest at ``path``, if the run exists."""
        data = read_json(path)
        if not isinstance(data, dict):
            return None
        return cls(
            sample=[str(k) for k in cast("list[object]", data["sample"])],
            completeness=int(data["completeness"]),
            images=int(data["images"]),
            pages=int(data["pages"]),
            all_chapters=bool(data.get("all_chapters", False)),
        )

    def save(self, path: Path) -> None:
        """Persist the manifest."""
        write_json_atomic(path, asdict(self))


class SourceState:
    """Mutable progress of one source in one run, saved after each step."""

    def __init__(self, path: Path, source_id: str) -> None:
        """Load (or start) the state for ``source_id``."""
        self.path = path
        data = cast("dict[str, object]", read_json(path, {}))
        self.id = str(data.get("id", source_id))
        self.prepared = bool(data.get("prepared", False))
        self.aborted = cast("str | None", data.get("aborted"))
        self.error = cast("str | None", data.get("error"))
        self.done = bool(data.get("done", False))
        self.titles = cast("dict[str, dict[str, object]]", data.get("titles", {}))
        self.chapters = cast("dict[str, dict[str, object]]", data.get("chapters", {}))
        self.images = cast("dict[str, dict[str, object]]", data.get("images", {}))
        self.observations = cast("list[list[object]]", data.get("observations", []))

    def observe(self, obs: Observation) -> None:
        """Remember one live request (saved with the next checkpoint)."""
        self.observations.append(
            [obs.at, obs.ok, round(obs.ms, 1), obs.kind, obs.status]
        )

    def save(self) -> None:
        """Checkpoint atomically."""
        write_json_atomic(
            self.path,
            {
                "id": self.id,
                "prepared": self.prepared,
                "aborted": self.aborted,
                "error": self.error,
                "done": self.done,
                "titles": self.titles,
                "chapters": self.chapters,
                "images": self.images,
                "observations": self.observations,
            },
        )

    def found(self) -> dict[str, dict[str, object]]:
        """Title results that matched, keyed by reference key."""
        return {k: v for k, v in self.titles.items() if v.get("status") == "found"}


class RunDir:
    """Layout of one run under the state directory."""

    def __init__(self, state_dir: Path, run_id: str) -> None:
        """Point at ``<state_dir>/runs/<run_id>``."""
        self.run_id = run_id
        self.root = state_dir / "runs" / run_id
        self.manifest_path = self.root / "manifest.json"

    def source(self, source_id: str) -> SourceState:
        """State of ``source_id`` in this run."""
        return SourceState(self.root / "sources" / f"{sha1(source_id)}.json", source_id)

    def evaluated_ids(self) -> list[str]:
        """Ids of every source this run has touched."""
        folder = self.root / "sources"
        if not folder.is_dir():
            return []
        return sorted(
            str(cast("dict[str, object]", read_json(p))["id"])
            for p in folder.glob("*.json")
        )
