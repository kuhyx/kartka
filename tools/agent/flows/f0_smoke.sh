#!/bin/bash
# f0 smoke: the agent instance boots, shows the five-tab shell, a tap changes
# the screen, and a screenshot is not blank. Exit 0 = pass; otherwise the
# failing step and a screenshot path are printed.
#   tools/agent/flows/f0_smoke.sh
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f0
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly TABS=(Library Updates Browse Sources More)

step "start the isolated agent instance"
check "$AGENT" start

step "wait for the Library/Updates/Browse/Sources/More shell"
pop_to_tabs
for tab in "${TABS[@]}"; do
  check drive wait "$tab" --timeout 20 >/dev/null
done

step "tree lists every tab label"
tree="$(check drive tree)"
for tab in "${TABS[@]}"; do
  grep -q "\"${tab} | Tab [0-9] of 5\"" <<<"$tree" || fail "tab \"$tab\" missing from tree"
done

step "tap Library: Library becomes the current tab"
check drive tap Library >/dev/null
check drive wait Library --flag current --timeout 5

step "tap Browse"
check drive tap Browse

step "Browse is now the current tab and Library is not"
check drive wait Browse --flag current --timeout 5
check drive wait Library --flag current --gone --timeout 5

step "screenshot is not blank"
check drive shot --min-colours 16

echo "[f0] PASS"
