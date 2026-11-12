# Copyright (c) 2026 Krzysztof Rudnicki
"""Reading the app's synced scoring profile (sealed under ``/kartka-e2e``)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING
lazy from collections.abc import Callable

from source_eval.e2e import E2eLockedError, open_cipher, open_node, read_passphrase
from source_eval.profile import (
    DEFAULT,
    SETTING_NODE,
    SETTING_REL,
    Profile,
    parse_profile,
)

if TYPE_CHECKING:
    from source_eval.report import RtdbReader


def load_profile(
    open_reader: Callable[[], RtdbReader],
    passphrase: Callable[[], str] = read_passphrase,
) -> tuple[Profile, str | None]:
    """The active scoring profile (the app's synced setting) and a warning.

    Read-only; ``open_reader`` is called here so a failed sign-in is covered.
    The node is sealed by the app; it opens with the shared crdt-sync password
    (``passphrase``). No custom profile (no e2e header yet, node absent or
    removed) is DEFAULT with no warning; a locked, unreadable or invalid one
    is DEFAULT plus a warning saying why.
    """
    try:
        reader = open_reader()
        cipher = open_cipher(reader, passphrase)
        stored = None if cipher is None else reader.get(SETTING_NODE)
    except E2eLockedError as error:
        return DEFAULT, f"profile locked ({error}); scoring with DEFAULT"
    except Exception as error:  # noqa: BLE001 -- any failure falls back
        return DEFAULT, f"profile unreadable ({error}); scoring with DEFAULT"
    if stored is None or cipher is None:
        return DEFAULT, None
    node = open_node(cipher, SETTING_REL, stored)
    if node is None:
        return DEFAULT, "profile does not open; scoring with DEFAULT"
    return _from_node(node)


def _from_node(node: dict[str, object]) -> tuple[Profile, str | None]:
    """The profile in an opened settings node; a removal node is DEFAULT."""
    value = node.get("value")
    if value is None:
        return DEFAULT, None  # a removal node: only {key, hlc}
    try:
        parsed = parse_profile(json.loads(value)) if isinstance(value, str) else None
    except ValueError:
        parsed = None
    if parsed is None:
        return DEFAULT, "profile invalid; scoring with DEFAULT"
    return parsed, None
