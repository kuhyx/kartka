# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import io

from hypothesis import given, settings
from hypothesis import strategies as st
from PIL import Image
import pytest

from source_eval.imagequality import estimate_jpeg_quality, measure, summarize
from source_eval.models import SourceError


def _jpeg(quality: int, size: tuple[int, int] = (64, 48)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (120, 30, 200)).save(buf, "JPEG", quality=quality)
    return buf.getvalue()


@settings(max_examples=40, deadline=None)
@given(st.integers(10, 100))
def test_jpeg_quality_round_trip(quality: int) -> None:
    sample = measure(_jpeg(quality))
    assert sample.fmt == "JPEG"
    assert sample.jpeg_quality is not None
    assert abs(sample.jpeg_quality - quality) <= 1


def test_estimate_is_order_independent() -> None:
    table = list(range(1, 65))
    assert estimate_jpeg_quality(table) == estimate_jpeg_quality(table[::-1])


def test_png_and_webp_have_no_jpeg_quality() -> None:
    for fmt in ("PNG", "WEBP"):
        buf = io.BytesIO()
        Image.new("RGB", (800, 1200)).save(buf, fmt)
        sample = measure(buf.getvalue())
        assert (sample.width, sample.height, sample.jpeg_quality) == (800, 1200, None)


def test_garbage_raises() -> None:
    with pytest.raises(SourceError, match="undecodable"):
        measure(b"<html>not an image</html>")


def test_summarize() -> None:
    samples: list[dict[str, object]] = [
        {"width": 1000, "jpegQuality": 80},
        {"width": 1200, "jpegQuality": None},
        {"width": 1400, "jpegQuality": 90},
    ]
    assert summarize(samples) == {
        "sampledPages": 3,
        "medianWidthPx": 1200,
        "medianJpegQuality": 85,
    }
    assert summarize([]) == {
        "sampledPages": 0,
        "medianWidthPx": None,
        "medianJpegQuality": None,
    }
