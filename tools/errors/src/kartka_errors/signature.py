# Copyright (c) 2026 Krzysztof Rudnicki
"""Group error reports: one signature per bug, however often it fires.

A signature is the error type, the message with its volatile parts
(numbers, ids, URLs) masked, and where it happened: the first app frame
without line numbers (so an edit elsewhere in the file does not split it),
else the route, else the entry kind.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

#: The longest normalised message kept in a signature.
MAX_MESSAGE = 160

_TYPE = re.compile(r"^(?:Unhandled error: )?([A-Z][\w$]*(?:Exception|Error))\b")
#: Dart errors whose ``toString`` does not name their type.
_DART_PREFIXES = {
    "Bad state": "StateError",
    "Invalid argument": "ArgumentError",
    "Unsupported operation": "UnsupportedError",
    "Null check operator": "TypeError",
    "Concurrent modification": "ConcurrentModificationError",
}
_URL = re.compile(r"(https?://\S+|<url>)")
_UUID = re.compile(
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.IGNORECASE
)
_HEX = re.compile(r"\b(?=[0-9a-f]*\d)[0-9a-f]{8,}\b", re.IGNORECASE)
_NUMBER = re.compile(r"\b\d+(\.\d+)?\b")
_SPACE = re.compile(r"\s+")
_FRAME = re.compile(r"^#\d+\s+")
_LINE_COL = re.compile(r"(\.dart)(:\d+)+\)")
#: Frames of the reporting plumbing itself, never the bug's location.
_PLUMBING = ("package:kartka/app/error_hooks.dart", "package:kartka/core/diagnostics/")


@dataclass(frozen=True)
class Signature:
    """What groups reports of one bug."""

    id: str
    type: str
    message: str
    where: str


def error_type(error: str, kind: str) -> str:
    """The exception type named by ``error``, else ``kind``."""
    if match := _TYPE.match(error):
        return match[1]
    for prefix, name in _DART_PREFIXES.items():
        if error.startswith(prefix):
            return name
    return kind


def normalise(message: str) -> str:
    """``message`` with URLs, uuids, long hex and numbers masked, trimmed."""
    text = _URL.sub("<url>", message)
    text = _UUID.sub("<uuid>", text)
    text = _HEX.sub("<hex>", text)
    text = _NUMBER.sub("<n>", text)
    return _SPACE.sub(" ", text).strip()[:MAX_MESSAGE]


def top_frame(stack: Sequence[str]) -> str | None:
    """The first ``package:kartka/`` frame outside the reporting plumbing."""
    for frame in stack:
        if "package:kartka/" in frame and not any(p in frame for p in _PLUMBING):
            return _LINE_COL.sub(r"\1)", _FRAME.sub("", frame.strip()))
    return None


def _strings(value: object) -> list[str]:
    return [str(v) for v in value] if isinstance(value, list) else []


def signature(entry: Mapping[str, object]) -> Signature:
    """The signature of one report (a decoded ``DiagnosticEntry``)."""
    kind = str(entry.get("kind", "?"))
    error = str(entry.get("error", ""))
    frame = top_frame(_strings(entry.get("stack")))
    route = entry.get("route")
    where = frame or (f"route {route}" if route else f"kind {kind}")
    kind_type = error_type(error, kind)
    message = normalise(error)
    digest = hashlib.sha1(  # noqa: S324 -- a grouping key, not security
        f"{kind_type}|{message}|{where}".encode()
    ).hexdigest()
    return Signature(digest[:10], kind_type, message, where)
