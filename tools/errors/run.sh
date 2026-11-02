#!/bin/bash
# ============================================================================
# run.sh -- kartka-errors from this checkout's own venv, at the repo root
# (the report goes to ~/.local/state/kartka-errors/fixme.md).
#
#   tools/errors/run.sh ingest               what the timer runs every 15 min
#   tools/errors/run.sh ingest --keep        read only, leave RTDB as it is
#   tools/errors/run.sh resolve <signature>  mark a fixed error resolved
#   tools/errors/run.sh render               rewrite fixme.md offline
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly HERE
readonly REPO="${HERE%/tools/errors}"

uv_bin="$(command -v uv || echo "${HOME}/.local/bin/uv")"
cd "${REPO}"
exec "${uv_bin}" run --frozen --quiet --project "${HERE}" kartka-errors "$@"
