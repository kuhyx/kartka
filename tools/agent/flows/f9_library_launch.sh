#!/bin/bash
# f9 library launch (library.load a133bbb8): reloads the app RUNS times and
# reads each launch's `perf.startup` marks from the agent's diagnostics log.
# The wait is library.shown - library.wait (what LibraryProbe uploads at
# 1 s). Prints the marks per launch; fails when any wait reaches LIMIT_MS.
#   tools/agent/flows/f9_library_launch.sh [limit_ms=1000 [runs=5]]
# Rebuild build/web first when lib/ changed.
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f9
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly LIMIT_MS="${1:-1000}"
readonly RUNS="${2:-5}"
readonly LOG="$AGENT_HOME/files/diagnostics/kartka-diagnostics.jsonl"

# startup_lines: how many perf.startup lines the log holds now.
startup_lines() { grep -c '"kind":"perf.startup"' "$LOG" 2>/dev/null || true; }

# wait_ms <marks>: library.shown - library.wait from one marks line; 0 when
# the grid never showed its spinner (no library.wait mark).
wait_ms() {
  local w s
  w="$(grep -oE 'library\.wait=[0-9]+' <<<"$1" | cut -d= -f2 || true)"
  s="$(grep -oE 'library\.shown=[0-9]+' <<<"$1" | cut -d= -f2 || true)"
  [[ -n "$s" ]] || return 1
  echo $((s - ${w:-$s}))
}

step "start the agent"
check "$AGENT" start >/dev/null
worst=0
for ((run = 1; run <= RUNS; run++)); do
  step "launch $run of $RUNS"
  before="$(startup_lines)"
  check drive eval 'location.reload()' >/dev/null
  marks=""
  for ((i = 0; i < 100; i++)); do
    if (($(startup_lines) > before)); then
      marks="$(grep '"kind":"perf.startup"' "$LOG" | tail -1 |
        sed -E 's/.*"error":"([^"]*)".*/\1/')"
      break
    fi
    sleep 0.1
  done
  [[ -n "$marks" ]] || fail "launch $run logged no perf.startup in 10 s"
  ms="$(wait_ms "$marks")" || fail "launch $run: no library.wait/shown in: $marks"
  echo "[f9]   wait ${ms} ms: $marks"
  ((ms > worst)) && worst="$ms"
done
echo "[f9] worst library wait ${worst} ms (limit ${LIMIT_MS} ms)"
((worst < LIMIT_MS)) || fail "library wait ${worst} ms >= ${LIMIT_MS} ms"
echo "[f9] PASS"
