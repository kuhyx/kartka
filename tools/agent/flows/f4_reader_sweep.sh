#!/bin/bash
# f4 reader sweep (971debc8): opens the newest chapter of the first N manga
# on the Updates tab, headless in the agent instance, and fails when one
# shows neither the reader nor the Retry icon within 1 s of the tap (a
# reader.open the user would wait on). Exit 0 = every chapter opened or
# failed fast; otherwise the failing step and a screenshot are printed.
#   tools/agent/flows/f4_reader_sweep.sh [count=3] [limit_ms=1000]
# Rebuild build/web first when lib/ changed (scripts/build_web.sh).
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f4
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly COUNT="${1:-3}"
readonly LIMIT_MS="${2:-1000}"
# The reader's full-screen tap zones (ready) or its Retry icon (failed fast).
readonly OPENED='^#[0-9]+ button "Retry"|^#[0-9]+ button "" \[tap\] @0,0 '

now_ms() { date +%s%3N; }

# The manga tiles on Updates: buttons after "Check for updates", by label.
update_titles() {
  drive tree | sed -n '/"Check for updates"/,$p' | tail -n +2 |
    sed -nE 's/^#[0-9]+ button "([^"]+)" \[tap\].*/\1/p' | head -n "$COUNT"
}

# Polls the tree until the reader or its Retry shows; prints the ms taken.
time_open() {
  local start=$1 deadline=$(($1 + 10000))
  while (($(now_ms) < deadline)); do
    if drive tree 2>/dev/null | grep -qE "$OPENED"; then
      echo $(($(now_ms) - start))
      return 0
    fi
  done
  return 1
}

# Escape closes the reader (ReaderIntent.back) and the Updates sheet.
to_tabs() {
  local i
  for ((i = 0; i < 4; i++)); do
    if ! drive tree 2>/dev/null |
      grep -qE '^#[0-9]+ (region "Dialog"|button "" \[tap\] @0,0 )'; then
      on_tabs && return 0
    fi
    check drive key Escape >/dev/null
    sleep 0.3
  done
  pop_to_tabs
}

step "start the isolated agent instance"
check "$AGENT" start >/dev/null

step "open the Updates tab"
to_tabs
check drive tap Updates >/dev/null
check drive wait "Check for updates" --timeout 20 >/dev/null

# The feed loads after the tab shows: give it up to ~10 s.
titles=()
for ((i = 0; i < 20 && ${#titles[@]} == 0; i++)); do
  mapfile -t titles < <(update_titles)
  ((${#titles[@]} > 0)) || sleep 0.5
done
((${#titles[@]} > 0)) || fail "Updates lists no manga"

for ((n = 0; n < ${#titles[@]}; n++)); do
  # Re-read the tile: reading a chapter changes its "N unread | " label.
  title="$(update_titles | sed -n "$((n + 1))p")"
  [[ -n "$title" ]] || fail "Updates tile $((n + 1)) is gone"
  step "open the newest chapter of \"$title\""
  check drive tap "$title" >/dev/null
  check drive wait "Open manga" --timeout 10 >/dev/null
  # The newest chapter: the first button under the sheet's "Open manga".
  chapter="$(drive tree | sed -n '/"Open manga"/,$p' | tail -n +2 |
    sed -nE 's/^#[0-9]+ button "([^"]+)" \[tap\].*/\1/p' | head -n 1)"
  [[ -n "$chapter" ]] || fail "no chapter listed for \"$title\""
  start="$(now_ms)"
  check drive tap "$chapter" >/dev/null
  ms="$(time_open "$start")" || fail "\"$chapter\" showed neither pages nor Retry in 10 s"
  echo "[f4]   $chapter: ${ms} ms"
  ((ms <= LIMIT_MS)) || fail "\"$chapter\" took ${ms} ms to open (limit ${LIMIT_MS})"

  step "leave the reader"
  to_tabs
  check drive tap Updates >/dev/null
done

echo "[f4] PASS"
