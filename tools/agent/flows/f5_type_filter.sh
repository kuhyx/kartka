#!/bin/bash
# f5 type filter: in a source's listing the content-type button opens a
# sheet of three ticked checkboxes (Manga, Manhwa, Manhua); unticking all
# three empties the listing with a hint icon, ticking one brings it back.
# Exit 0 = pass; otherwise the failing step and a screenshot are printed.
#   tools/agent/flows/f5_type_filter.sh [source name, default MangaDex]
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f5
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly SOURCE="${1:-MangaDex}"
readonly TYPES=(Manga Manhwa Manhua)

# Taps checkbox $1 and waits until its checked flag is $2 (on|off).
tick() {
  local gone=()
  [[ "$2" == off ]] && gone=(--gone)
  check drive tap "$1" >/dev/null
  check drive wait "$1" --flag checked "${gone[@]}" --timeout 5 >/dev/null
}

# Opens the type sheet and lets its slide-in finish: a tap during the
# animation lands where the row was a frame ago and misses.
open_sheet() {
  check drive wait "Content types" --timeout 15 >/dev/null
  check drive tap "Content types" >/dev/null
  check drive wait Manhua --timeout 5 >/dev/null
  sleep 0.5
}

step "start the isolated agent instance"
check "$AGENT" start
drive key Escape >/dev/null 2>&1 || true # a sheet left open by a failed run
pop_to_tabs

step "open $SOURCE from Browse"
check drive tap Browse >/dev/null
check drive wait "$SOURCE" --timeout 20 >/dev/null
check drive tap "$SOURCE" >/dev/null
check drive wait "Content types" --timeout 20 >/dev/null

step "the sheet lists the three types; tick any unticked one"
open_sheet
check drive wait Manga --timeout 5 >/dev/null
for t in "${TYPES[@]}"; do
  # A stored older choice (e.g. manga only) shows fewer ticks.
  drive wait "$t" --flag checked --timeout 1 >/dev/null 2>&1 || tick "$t" on
done
check drive shot >/dev/null

step "untick all three: the listing is empty with a hint icon"
for t in "${TYPES[@]}"; do tick "$t" off; done
check drive key Escape >/dev/null
check drive wait "No content type ticked" --timeout 10 >/dev/null

step "tick Manga again: the hint goes"
open_sheet
tick Manga on
check drive key Escape >/dev/null
check drive wait "No content type ticked" --gone --timeout 20 >/dev/null

step "restore every type for the next run"
open_sheet
tick Manhwa on
tick Manhua on
check drive key Escape >/dev/null
check drive shot --min-colours 16

echo "[f5] PASS"
