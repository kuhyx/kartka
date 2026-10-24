# Copyright (c) 2026 Krzysztof Rudnicki
"""Schema-less protobuf wire decoding, enough to read an extension index.

Keiyoushi publishes its index as gzipped protobuf (``index.pb``). Pulling in
protoc for a handful of string and varint fields would cost more than these
forty lines.
"""

from __future__ import annotations

from collections.abc import Iterator

Value = int | bytes

_VARINT, _I64, _LEN, _I32 = 0, 1, 2, 5
_FIXED = {_I64: 8, _I32: 4}


def _varint(buf: bytes, pos: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        if pos >= len(buf):
            msg = "truncated varint"
            raise ValueError(msg)
        byte = buf[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:  # noqa: PLR2004 -- continuation bit
            return result, pos


def iter_fields(buf: bytes) -> Iterator[tuple[int, Value]]:
    """Yield ``(field number, value)``; LEN fields come back as bytes."""
    pos = 0
    while pos < len(buf):
        key, pos = _varint(buf, pos)
        number, wire = key >> 3, key & 7
        if wire == _VARINT:
            value, pos = _varint(buf, pos)
            yield number, value
            continue
        if wire == _LEN:
            size, pos = _varint(buf, pos)
        elif wire in _FIXED:
            size = _FIXED[wire]
        else:
            msg = f"unsupported wire type {wire}"
            raise ValueError(msg)
        if pos + size > len(buf):
            msg = "truncated field"
            raise ValueError(msg)
        yield number, buf[pos : pos + size]
        pos += size


def group(buf: bytes) -> dict[int, list[Value]]:
    """Collect every value of every field number, in order."""
    out: dict[int, list[Value]] = {}
    for number, value in iter_fields(buf):
        out.setdefault(number, []).append(value)
    return out


def text(fields: dict[int, list[Value]], number: int, default: str = "") -> str:
    """First value of ``number`` decoded as UTF-8."""
    values = fields.get(number)
    if not values or not isinstance(values[0], bytes):
        return default
    return values[0].decode("utf-8", errors="replace")


def integer(fields: dict[int, list[Value]], number: int, default: int = 0) -> int:
    """First value of ``number`` as an integer."""
    values = fields.get(number)
    if not values or not isinstance(values[0], int):
        return default
    return values[0]
