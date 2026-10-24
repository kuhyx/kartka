#!/usr/bin/env python3
"""Fail unless coverage/lcov.info covers every line of every lib/ file.

`flutter test --coverage` only reports files some test loaded, so a 100 %
figure can be hollow; test/all_imports_test.dart loads every lib/ file that
does not opt out with `// coverage:ignore-file` (thin platform wiring, with
a reason on the next line), so every file with executable lines is here.

Several reports (one per test directory, when a full run does not fit the
memory cap) are merged line by line.

Usage: scripts/check_coverage.py [lcov path ...] [--min PERCENT]
Exit: 0 ok | 1 below target or unloaded files | 2 no report
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def parse_lcov(texts: list[str]) -> dict[str, tuple[int, int, list[int]]]:
    """Map source file -> (hit lines, total lines, missed line numbers)."""
    hits: dict[str, dict[int, int]] = {}
    for text in texts:
        for block in text.split("end_of_record"):
            source = re.search(r"^SF:(.*)$", block, re.M)
            if not source:
                continue
            lines = hits.setdefault(source.group(1), {})
            for n, h in re.findall(r"^DA:(\d+),(\d+)", block, re.M):
                lines[int(n)] = max(lines.get(int(n), 0), int(h))
    files: dict[str, tuple[int, int, list[int]]] = {}
    for name, lines in hits.items():
        missed = sorted(n for n, h in lines.items() if h == 0)
        files[name] = (len(lines) - len(missed), len(lines), missed)
    return files


def main() -> int:
    """Check the report; print gaps."""
    parser = argparse.ArgumentParser()
    parser.add_argument("lcov", nargs="*", default=["coverage/lcov.info"])
    parser.add_argument("--min", type=float, default=100.0)
    args = parser.parse_args()
    reports = [Path(r) for r in args.lcov]
    absent = [r for r in reports if not r.exists()]
    if absent:
        print(f"no coverage report at {absent[0]}", file=sys.stderr)
        return 2
    files = parse_lcov([r.read_text() for r in reports])
    hit = sum(v[0] for v in files.values())
    total = sum(v[1] for v in files.values()) or 1
    percent = 100 * hit / total
    for name, (h, t, missed) in sorted(files.items()):
        if h < t:
            print(f"{name}: {h}/{t}, missed lines {missed[:20]}")
    print(f"line coverage {hit}/{total} = {percent:.2f}% ({len(files)} files)")
    return 0 if percent >= args.min else 1


if __name__ == "__main__":
    sys.exit(main())
