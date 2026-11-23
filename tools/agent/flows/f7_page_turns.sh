#!/bin/bash
# f7 page turns (28fffd0a): opens an older chapter of a manga that is NOT in
# the library (as f6), then turns TURNS pages with PageDown, reading each
# for READ_MS once it shows (a reader's pace). Each turn is timed until the
# shown page has no spinner: a loading page is a semantics node labelled
# with its number at @0,0, the wait `reader.page` reports. Prints the ms
# per turn; exits 1 when one is over LIMIT_MS. A page's image cached by the
# browser from an earlier run loads at once: use F7_CHAPTER for fresh ones.
#   tools/agent/flows/f7_page_turns.sh [limit_ms=1000] [turns=8] [read_ms=1500]
# F7_SOURCE / F7_TITLE / F7_CHAPTER pick the manga. Combine with
# `kartka_agent.sh fault '*' slow-images:<ms>` (every page image <ms> late).
# Rebuild build/web first when lib/ changed (scripts/build_web.sh).
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f7
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly LIMIT_MS="${1:-1000}"
readonly TURNS="${2:-8}"
readonly READ_MS="${3:-1500}"
readonly SOURCE="${F7_SOURCE:-M | Built-in | MangaDex}"
readonly DEFAULT_TITLE="The Guy She Was Interested in Wasn't a Guy at All"
readonly TITLE="${F7_TITLE:-$DEFAULT_TITLE}"
readonly CHAPTER_ROW="${F7_CHAPTER:-8}"
# A page still loading: its number, alone, filling the screen at the origin.
readonly SPINNER='^#[0-9]+ flt-semantics "[0-9]+" @0,0 '
# shellcheck source-path=SCRIPTDIR source=reader_nav.sh
source "$(dirname "${BASH_SOURCE[0]}")/reader_nav.sh"

# Prints the ms since $1 until the shown page has no spinner (15 s cap).
time_page() {
  local start=$1 deadline=$(($1 + 15000))
  while (($(now_ms) < deadline)); do
    if ! drive tree 2>/dev/null | grep -E "$SPINNER" >/dev/null; then
      echo "$(($(now_ms) - start))"
      return 0
    fi
  done
  return 1
}

# Reads the shown page for READ_MS, counted from when it showed (a wait
# does not shorten the reading).
read_page() { sleep "$((READ_MS / 1000)).$(printf '%03d' $((READ_MS % 1000)))"; }

open_reader
# The open's own wait: page 1 had no chance to be fetched ahead (only the
# Updates warmer hides it). Then page 1 is read like any other.
ms="$(time_page "$(now_ms)")" || fail "page 1 spun over 15 s"
echo "[f7]   page 1 after the open: ${ms} ms more"
read_page
worst=0
for ((turn = 1; turn <= TURNS; turn++)); do
  step "turn $turn"
  start="$(now_ms)"
  check drive key PageDown >/dev/null
  ms="$(time_page "$start")" || fail "turn $turn: the page spun over 15 s"
  h="$(header)"
  echo "[f7]   turn $turn: ${h:-?}: ${ms} ms"
  ((ms > worst)) && worst=$ms
  read_page
done
echo "[f7] worst turn: ${worst} ms"
((worst <= LIMIT_MS)) || fail "a page spun ${worst} ms (limit ${LIMIT_MS})"

step "leave the reader"
to_tabs
echo "[f7] PASS"
