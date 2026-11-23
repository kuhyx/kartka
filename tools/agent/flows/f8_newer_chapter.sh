#!/bin/bash
# f8 newer chapter (19643be5, C4): a chapter released after the stored
# chapter list was saved. With `hide-newest` on, it opens a MangaDex manga
# outside the library (as f6), so the stored list ends one chapter early;
# then it clears the fault, opens that stored newest chapter and swipes past
# its end. Passes when the newer chapter's page 1 shows (the fresh list
# named it) within LIMIT_MS, not the end icon.
#   tools/agent/flows/f8_newer_chapter.sh [limit_ms=1000]
# F8_TITLE picks the manga. Rebuild build/web first when lib/ changed.
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f8
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly LIMIT_MS="${1:-1000}"
readonly SOURCE="M | Built-in | MangaDex"
readonly DEFAULT_TITLE="The Guy She Was Interested in Wasn't a Guy at All"
readonly TITLE="${F8_TITLE:-$DEFAULT_TITLE}"
# shellcheck disable=SC2034 # read by reader_nav.sh
readonly CHAPTER_ROW=1
# shellcheck source-path=SCRIPTDIR source=reader_nav.sh
source "$(dirname "${BASH_SOURCE[0]}")/reader_nav.sh"
trap '"$AGENT" fault clear >/dev/null 2>&1 || true' EXIT

step "start the agent; MangaDex's feed hides its newest chapter"
check "$AGENT" start >/dev/null
"$AGENT" fault api.mangadex.org hide-newest >/dev/null
to_tabs
step "open \"$TITLE\" (its chapter list is stored without the newest)"
check drive tap Browse >/dev/null
check drive wait "$SOURCE" --timeout 20 >/dev/null
sleep 2
check drive tap "$SOURCE" >/dev/null
check drive wait "$TITLE" --timeout 20 >/dev/null
check drive tap "$TITLE" >/dev/null
check drive wait "Show details" --timeout 20 >/dev/null
row=""
for ((i = 0; i < 20 && ${#row} == 0; i++)); do
  row="$(drive tree | sed -nE 's/^#[0-9]+ button "(Ch\.[^"]+)" \[tap\].*/\1/p' | head -1)"
  [[ -n "$row" ]] || sleep 0.5
done
echo "[f8]   newest row while hidden: $row"
step "the newer chapter is out again (fault cleared); open the stored newest"
"$AGENT" fault clear >/dev/null
check drive tap "$row" >/dev/null
opened=0
for ((i = 0; i < 100 && opened == 0; i++)); do
  if drive tree 2>/dev/null | grep -E '^#[0-9]+ button "" \[tap\] @0,0 ' >/dev/null; then
    opened=1
  fi
done
((opened)) || fail "never opened"
check drive tap-xy 700 450 >/dev/null
h="$(wait_header)" || fail "no controls"
IFS='|' read -r name page count <<<"$h"
step "page to the end of \"$name\" ($page / $count) and swipe past it"
for ((p = page; p < count; p++)); do
  check drive key PageDown >/dev/null
done
start="$(now_ms)"
check drive key PageDown >/dev/null
deadline=$((start + 15000))
got=""
while (($(now_ms) < deadline)); do
  h="$(header)"
  rest="${h#*|}"
  if [[ -n "$h" && "${h%%|*}" != "$name" && "${rest%%|*}" == 1 ]]; then
    got="$h"
    break
  fi
done
[[ -n "$got" ]] || fail "no newer chapter after \"$name\" in 15 s"
ms=$(($(now_ms) - start))
echo "[f8]   $name -> ${got%%|*}: ${ms} ms"
((ms <= LIMIT_MS)) || fail "the newer chapter took ${ms} ms (limit ${LIMIT_MS})"
step "leave the reader"
to_tabs
echo "[f8] PASS"
