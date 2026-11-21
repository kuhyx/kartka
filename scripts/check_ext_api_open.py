#!/usr/bin/env python3
"""Fail when R8 sealed the extension host API in a release APK.

Keiyoushi extensions subclass `eu.kanade.tachiyomi.**` (HttpSource,
ParsedHttpSource, ...) and override its `open` members. R8 sees no
override inside kartka, so with `allowoptimization` it marks those
classes and methods `final`, and ART then refuses the extension:
"overrides final method". This compares the Kotlin compile output
(javap) with the shipped dex (baksmali) and lists every class or method
that was open in Kotlin and is final, or gone, in the APK.

Usage: check_ext_api_open.py <apk> <kotlin-classes-dir>
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PKG = "eu/kanade/tachiyomi"
_JAVAP_CLASS = re.compile(r"^(?P<mods>[\w ]*?)(class|interface) (?P<name>[\w.$]+)")
_MODS = r"(?:(?:public|protected|private|static|final|abstract|synchronized|native|default) )+"
_JAVAP_METHOD = re.compile(rf"^\s+(?P<mods>{_MODS})(?:<.+?> )?[\w.$<>\[\], ?]+ (?P<name>[\w$]+)\(")
_SMALI_METHOD = re.compile(r"^\.method (?P<mods>[\w -]*?)(?P<name>[\w$<>-]+)\(")


def kotlin_open(classes: Path) -> dict[str, set[str]]:
    """Open (non-final) public/protected methods per open class, from javap."""
    files = sorted(str(p) for p in (classes / PKG).rglob("*.class"))
    out = subprocess.run(["javap", "-p", *files], capture_output=True, text=True, check=True).stdout
    result: dict[str, set[str]] = {}
    current: str | None = None
    for line in out.splitlines():
        if m := _JAVAP_CLASS.match(line):
            mods = m["mods"].split()
            current = None if "final" in mods else m["name"].replace(".", "/")
            if current:
                result[current] = set()
        elif current and (m := _JAVAP_METHOD.match(line)):
            mods = m["mods"].split()
            if not {"final", "static", "private"} & set(mods):
                result[current].add(m["name"])
    return result


def dex_final(apk: Path, work: Path) -> dict[str, tuple[bool, set[str], set[str]]]:
    """Per host class in the APK: (class is final, final methods, all methods)."""
    with zipfile.ZipFile(apk) as z:
        dexes = [n for n in z.namelist() if re.fullmatch(r"classes\d*\.dex", n)]
        z.extractall(work, dexes)
    result: dict[str, tuple[bool, set[str], set[str]]] = {}
    for dex in dexes:
        out = work / f"{dex}.smali"
        subprocess.run(["baksmali", "d", "-o", str(out), str(work / dex)], check=True, capture_output=True)
        for f in (out / PKG).rglob("*.smali") if (out / PKG).exists() else []:
            name = str(f.relative_to(out).with_suffix(""))
            lines = f.read_text().splitlines()
            is_final = " final " in f" {lines[0]} "
            finals: set[str] = set()
            every: set[str] = set()
            for line in lines:
                if m := _SMALI_METHOD.match(line):
                    every.add(m["name"])
                    if "final" in m["mods"].split():
                        finals.add(m["name"])
            result[name] = (is_final, finals, every)
    return result


def problems(kt: dict[str, set[str]], dex: dict[str, tuple[bool, set[str], set[str]]]) -> list[str]:
    """Every class/method sealed or dropped by R8."""
    found: list[str] = []
    for cls, methods in sorted(kt.items()):
        if cls not in dex:
            found.append(f"{cls}: class missing from the APK")
            continue
        is_final, finals, every = dex[cls]
        if is_final:
            found.append(f"{cls}: class is final")
        found += [f"{cls}.{m}: final" for m in sorted(methods & finals)]
        found += [f"{cls}.{m}: missing" for m in sorted(methods - every)]
    return found


def main(argv: list[str]) -> int:
    """Entry point: prints problems, exit 1 if any."""
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory() as tmp:
        found = problems(kotlin_open(Path(argv[2])), dex_final(Path(argv[1]), Path(tmp)))
    for p in found:
        print(p)
    print(f"check_ext_api_open: {len(found)} sealed member(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
