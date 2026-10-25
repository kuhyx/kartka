#!/bin/bash
# Weekly full evaluation: refresh candidates, measure every source against the
# same stratified sample, rank, write out/latest.json and publish to RTDB
# /kartka/source_health. Every step is a loop of < 60 s batches (batch.sh),
# so the run is resumable at any point: rerunning the same ISO week continues.
#
# The sample ramps (source-eval ramp): +50 titles while the previous run took
# <= 2 h, -50 when it went over, within [200, 500]; KARTKA_EVAL_SAMPLE
# overrides it. Sources the last published run hard-cut get one re-probe.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${KARTKA_EVAL_RUN:-$(date -u +%G-W%V)}"
readonly HERE RUN
readonly WORKERS="${KARTKA_EVAL_WORKERS:-128}"
readonly INFLIGHT="${KARTKA_EVAL_INFLIGHT:-64}"
# shellcheck source=SCRIPTDIR/batch.sh
source "${HERE}/systemd/batch.sh"

sample=()
[[ -z ${KARTKA_EVAL_SAMPLE:-} ]] || sample=(--sample "${KARTKA_EVAL_SAMPLE}")

eval_once ramp start --run "${RUN}" "${sample[@]}"
eval_batches candidates
eval_batches reference
eval_once init-run --run "${RUN}" --ramp --reprobe
eval_batches enrich --run "${RUN}"
eval_batches run --run "${RUN}" --workers "${WORKERS}" --inflight "${INFLIGHT}"
eval_batches report --run "${RUN}" --publish
eval_once ramp finish --run "${RUN}"
