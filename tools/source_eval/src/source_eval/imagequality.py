# Copyright (c) 2026 Krzysztof Rudnicki
"""Page-image quality: pixel width and the JPEG quality it was saved at.

The JPEG estimate inverts the IJG (libjpeg) quality scaling of the standard
luminance table. It compares table *sums*, so it does not care whether the
decoder reports the table in zigzag or natural order.
"""

from __future__ import annotations

from dataclasses import dataclass
import io
from statistics import median

from PIL import Image, UnidentifiedImageError

from source_eval.models import SourceError

# Annex K.1 luminance table (any order: only its entries matter).
_STD_LUMA = (
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
)  # fmt: skip
_MAX_Q = 100


def _scaled_sum(quality: int) -> int:
    scale = 5000 // quality if quality < 50 else 200 - 2 * quality  # noqa: PLR2004
    return sum(min(255, max(1, (v * scale + 50) // 100)) for v in _STD_LUMA)


_SUMS = {q: _scaled_sum(q) for q in range(1, _MAX_Q + 1)}


def estimate_jpeg_quality(luma_table: list[int]) -> int:
    """IJG quality (1-100) whose scaled standard table best fits ``luma_table``."""
    observed = sum(luma_table)
    return min(_SUMS, key=lambda q: (abs(_SUMS[q] - observed), -q))


@dataclass(frozen=True, slots=True)
class ImageSample:
    """Measurements of one page image."""

    width: int
    height: int
    fmt: str
    jpeg_quality: int | None


def measure(data: bytes) -> ImageSample:
    """Read the header of ``data``; no full decode is needed."""
    try:
        with Image.open(io.BytesIO(data)) as im:
            quality = None
            tables = getattr(im, "quantization", None)
            if im.format == "JPEG" and tables:
                quality = estimate_jpeg_quality(list(tables[0]))
            return ImageSample(im.width, im.height, str(im.format), quality)
    except (UnidentifiedImageError, OSError) as exc:
        msg = f"undecodable image: {exc}"
        raise SourceError(msg) from exc


def summarize(samples: list[dict[str, object]]) -> dict[str, object]:
    """Contract ``imageQuality`` block from stored samples (JPEG-only quality)."""
    widths = [int(str(s["width"])) for s in samples]
    qualities = [
        int(str(s["jpegQuality"])) for s in samples if s.get("jpegQuality") is not None
    ]
    return {
        "sampledPages": len(samples),
        "medianWidthPx": round(median(widths)) if widths else None,
        "medianJpegQuality": round(median(qualities)) if qualities else None,
    }
