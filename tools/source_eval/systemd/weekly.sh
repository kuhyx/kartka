#!/bin/bash
# Weekly full evaluation: refresh candidates, measure every source against the
# same stratified 200-title sample, rank, write out/latest.json and publish to
# RTDB /kartka/source_health. Resumable: rerunning the same ISO week continues.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${KARTKA_EVAL_RUN:-$(date -u +%G-W%V)}"
readonly HERE RUN
readonly SAMPLE="${KARTKA_EVAL_SAMPLE:-200}"

eval_cmd() { uv run --frozen --project "$HERE" source-eval "$@"; }

eval_cmd candidates
eval_cmd reference
eval_cmd init-run --run "$RUN" --sample "$SAMPLE"
eval_cmd enrich --run "$RUN"
eval_cmd run --run "$RUN" --workers 16
eval_cmd report --run "$RUN" --publish
