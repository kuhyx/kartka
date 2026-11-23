#!/bin/bash
# f6 chapter advance (19643be5): opens an older chapter of a manga that is
# NOT in the library (the agent is signed in to kuhy's real sync, so a
# library manga's read marks would move), pages to its last page and swipes
# past it, RUNS times in a row. Each run is timed from that swipe until the
# reader shows the next chapter (the controls' "<chapter> | p / n" header
# changes chapter): the chapter-edge spinner the user would wait on. Prints
# the ms per run; exits 1 when one is over LIMIT_MS.
#   tools/agent/flows/f6_chapter_advance.sh [limit_ms=1000] [runs=2]
# F6_SOURCE / F6_TITLE / F6_CHAPTER (row in the detail list, 1 = newest)
# pick the manga. Combine with `kartka_agent.sh fault <host> slow-details:900`
# (chapter list) or `slow-pages:900` (page lists).
# Rebuild build/web first when lib/ changed (scripts/build_web.sh).
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f6
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly LIMIT_MS="${1:-1000}"
readonly RUNS="${2:-2}"
readonly SOURCE="${F6_SOURCE:-M | Built-in | MangaDex}"
# Not in the library, on MangaDex's Popular page, chapters hosted there.
readonly DEFAULT_TITLE="The Guy She Was Interested in Wasn't a Guy at All"
readonly TITLE="${F6_TITLE:-$DEFAULT_TITLE}"
readonly CHAPTER_ROW="${F6_CHAPTER:-4}"
# shellcheck source-path=SCRIPTDIR source=reader_nav.sh
source "$(dirname "${BASH_SOURCE[0]}")/reader_nav.sh"

# Polls until the header shows page 1 of a chapter other than $1; prints
# the ms since $2. The next chapter's page 1 then shows in place of the
# spinner. (A list arriving on the edge renames the chapter, "Chapter" ->
# its name, but keeps the last page: not an advance.)
time_advance() {
  local from=$1 start=$2 h rest deadline=$(($2 + 15000))
  while (($(now_ms) < deadline)); do
    h="$(header)"
    rest="${h#*|}"
    if [[ -n "$h" && "${h%%|*}" != "$from" && "${rest%%|*}" == 1 ]]; then
      echo "$(($(now_ms) - start))|$h"
      return 0
    fi
  done
  return 1
}

open_reader

for ((run = 1; run <= RUNS; run++)); do
  IFS='|' read -r name page count <<<"$h"
  step "run $run: page to the end of \"$name\" ($page / $count)"
  for ((p = page; p < count; p++)); do
    check drive key PageDown >/dev/null
  done
  h="$(wait_header)" || fail "the header went away"
  [[ "$h" == "$name|$count|$count" ]] || fail "not on the last page: $h"
  start="$(now_ms)"
  check drive key PageDown >/dev/null
  out="$(time_advance "$name" "$start")" ||
    fail "\"$name\" never advanced to the next chapter in 15 s"
  ms="${out%%|*}"
  h="${out#*|}"
  echo "[f6]   run $run: ${name} -> ${h%%|*}: ${ms} ms"
  ((ms <= LIMIT_MS)) || fail "advancing took ${ms} ms (limit ${LIMIT_MS})"
done

step "leave the reader"
to_tabs
echo "[f6] PASS"
