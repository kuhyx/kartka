#!/bin/bash
# Uptime probe round: one request per source, as < 60 s batches (batch.sh).
# A source probed within the last 3 h (this round) is skipped, so a batch
# cut short by its budget resumes where it stopped.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly HERE
readonly WORKERS="${KARTKA_EVAL_PROBE_WORKERS:-64}"
readonly FRESH="${KARTKA_EVAL_PROBE_FRESH:-10800}"
# shellcheck source=SCRIPTDIR/batch.sh
source "${HERE}/systemd/batch.sh"

eval_batches probe --workers "${WORKERS}" --fresh "${FRESH}"
