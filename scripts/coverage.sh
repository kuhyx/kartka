#!/bin/bash

# ============================================================================
# Full suite with coverage, one test directory per run (a single run of the
# whole suite does not fit capped.sh's memory limit next to other jobs), then
# merge into coverage/lcov.info and require 100 % line coverage of lib/.
# Also covers the desktop/ wrapper package (desktop/coverage/lcov.info).
#
# Usage: scripts/coverage.sh        (exit 0 only at 100 % in both packages)
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
cd "${ROOT}"
rm -rf coverage
mkdir -p coverage

parts=()
for dir in test/*/; do
    name="$(basename "${dir}")"
    [[ "${name}" == helpers ]] && continue
    fvm flutter test --coverage --coverage-path="coverage/${name}.info" \
        --concurrency=1 --reporter=compact "${dir}"
    parts+=("coverage/${name}.info")
done
fvm flutter test --coverage --coverage-path=coverage/root.info \
    --reporter=compact test/*_test.dart
parts+=(coverage/root.info)
python3 scripts/check_coverage.py "${parts[@]}" --write-merged coverage/lcov.info

cd desktop
fvm dart test --coverage-path=coverage/lcov.info --reporter=compact
python3 ../scripts/check_coverage.py coverage/lcov.info
