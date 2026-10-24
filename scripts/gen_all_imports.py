"""Write kartka's test/all_imports/<group>_test.dart import files.

Lists every lib/**.dart file whose first 400 chars lack
`coverage:ignore-file` and that is not a `part of` file, grouped by the
first lib/ directory, so no file passes the 250-line cap.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

HEADER = """// GENERATED list for test/all_imports_test.dart: loads every lib/{group}
// file on the VM so `flutter test --coverage` reports it.
// ignore_for_file: unused_import
import 'package:flutter_test/flutter_test.dart';
"""

FOOTER = """
void main() {{
  test('every lib/{group} file loads', () {{}});
}}
"""


def groups(root: Path) -> dict[str, list[str]]:
    """Return import lines per top-level lib directory."""
    out: dict[str, list[str]] = defaultdict(list)
    for f in sorted((root / "lib").rglob("*.dart")):
        head = f.read_text()[:400]
        if "coverage:ignore-file" in head or re.search(r"^part of ", head, re.MULTILINE):
            continue
        rel = f.relative_to(root / "lib").as_posix()
        group = rel.split("/")[0] if "/" in rel else "root"
        out[group].append(f"import 'package:kartka/{rel}';")
    return out


def main(root: Path) -> int:
    """Rewrite test/all_imports/ from scratch."""
    target = root / "test" / "all_imports"
    target.mkdir(exist_ok=True)
    for old in target.glob("*_test.dart"):
        old.unlink()
    for group, lines in groups(root).items():
        body = HEADER.format(group=group) + "\n".join(sorted(lines)) + "\n"
        path = target / f"{group}_imports_test.dart"
        path.write_text(body + FOOTER.format(group=group))
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
