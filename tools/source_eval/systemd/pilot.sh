#!/bin/bash
# Pilot of the weekly run at a bigger sample: measure a few sources against
# N reference titles in an ISOLATED run, to time it before the weekly unit
# changes. Never touches the weekly state, out/latest.json or RTDB.
#
# Start it as its own user unit (copy of kartka-source-eval-full's limits):
#   systemd-run --user --unit kartka-source-eval-pilot \
#     -p Requires=kartka-suwayomi-eval.service \
#     -p After=kartka-suwayomi-eval.service -p Nice=19 \
#     -p IOSchedulingClass=idle -p MemoryMax=2G -p CPUQuota=25% \
#     -E PILOT_DIR=<dir> -E PILOT_IDS="<id> <id> ..." <this script>
#
# PILOT_DIR gets state/, cache/ (cold, so timings are honest) and
# report.json. Resumable: restarting continues the same run.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly HERE
readonly PILOT_DIR="${PILOT_DIR:?set PILOT_DIR}"
readonly PILOT_IDS="${PILOT_IDS:?set PILOT_IDS (space-separated source ids)}"
readonly RUN="${PILOT_RUN:-pilot-500}"
readonly SAMPLE="${PILOT_SAMPLE:-500}"
readonly WEEKLY_STATE="${HOME}/.local/state/kartka-source-eval"

die() {
	echo "pilot.sh: $*" >&2
	exit 1
}

# The pilot must never share the weekly run's state (or its run ids).
case "$(realpath -m "${PILOT_DIR}")" in
"$(realpath -m "${WEEKLY_STATE}")"*) die "PILOT_DIR is inside the weekly state" ;;
esac
[[ ${RUN} != [0-9][0-9][0-9][0-9]-W[0-9][0-9] ]] || die "run id ${RUN} looks weekly"

export XDG_STATE_HOME="${PILOT_DIR}/state" XDG_CACHE_HOME="${PILOT_DIR}/cache"
mkdir -p "${XDG_STATE_HOME}" "${XDG_CACHE_HOME}"
read -r -a ids <<<"${PILOT_IDS}"

eval_cmd() { uv run --frozen --project "${HERE}" source-eval "$@"; }

"${HERE}/systemd/eval_server_ready.sh"
eval_cmd init-run --run "${RUN}" --sample "${SAMPLE}"
eval_cmd enrich --run "${RUN}"
date -u +%s >"${PILOT_DIR}/run_started"
eval_cmd run --run "${RUN}" --ids "${ids[@]}" --workers 16
date -u +%s >"${PILOT_DIR}/run_finished"
eval_cmd report --run "${RUN}" --out "${PILOT_DIR}/report.json" --weights default
echo "pilot.sh: done; report at ${PILOT_DIR}/report.json"
