#!/bin/bash
# Weekly full evaluation: refresh candidates, measure every source against the
# same stratified sample, rank, write out/latest.json and publish to RTDB
# /kartka/source_health. Every step is a loop of < 60 s batches (batch.sh),
# so the run is resumable at any point: rerunning the same ISO week continues.
#
# The sample ramps (source-eval ramp): +50 titles while the previous run took
# <= 2 h, -50 when it went over, within [200, 500]; KARTKA_EVAL_SAMPLE
# overrides it. Sources the last published run hard-cut get one re-probe.
# A week that already finished its publish is a no-op (Persistent=true reruns
# a missed or moved timer; that must not re-publish or log a second ramp).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${KARTKA_EVAL_RUN:-$(date -u +%G-W%V)}"
readonly HERE RUN
readonly WORKERS="${KARTKA_EVAL_WORKERS:-128}"
# In flight ~= req/s x latency. The eval Suwayomi (3 cores) should take ~25
# req/s; 21 req/s needs ~21-40 slots at 1-2 s a request, and every slot above
# capacity only queues (64 in flight on one core: median 7.6 s, p90 12 s of the
# 20 s timeout). 48 keeps the queue near 2 s. Re-measure 32/48/64 after changes.
readonly INFLIGHT="${KARTKA_EVAL_INFLIGHT:-32}"
# shellcheck source=SCRIPTDIR/batch.sh
source "${HERE}/systemd/batch.sh"

sample=()
[[ -z ${KARTKA_EVAL_SAMPLE:-} ]] || sample=(--sample "${KARTKA_EVAL_SAMPLE}")

rc=0
eval_once published --run "${RUN}" >/dev/null || rc=$?
case "${rc}" in
0)
	echo "weekly: ${RUN} already published, nothing to do"
	exit 0
	;;
"${MORE_WORK}") ;;
*) exit "${rc}" ;;
esac

eval_once ramp start --run "${RUN}" "${sample[@]}"
eval_batches candidates
eval_batches reference
eval_once init-run --run "${RUN}" --ramp --reprobe
eval_batches enrich --run "${RUN}"
eval_batches run --run "${RUN}" --workers "${WORKERS}" --inflight "${INFLIGHT}"
eval_batches report --run "${RUN}" --publish
eval_once ramp finish --run "${RUN}"
