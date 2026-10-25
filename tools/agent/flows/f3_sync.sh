#!/bin/bash
# f3 sync: get the agent instance signed into the shared sync account from
# the seeded session (no password: the account is Google-only), then
# optionally assert a chapter shows as read.
#
#   tools/agent/flows/f3_sync.sh                                  # sign in only
#   tools/agent/flows/f3_sync.sh "<manga title>" "<chapter label>" [trigger_epoch]
#
# Signed out with no ~/.config/kartka-agent/firebase_auth.json: exits 1 with
# the one command kuhy runs (a Google consent tap) to write it. With the
# seed: restarts the agent so a fresh wrapper serves it to a fresh page,
# which adopts it (DOCS-contracts-runtime §17). Never types a credential.
#
# The assert polls until trigger_epoch + 10 s (default: now + 10 s) for the
# chapter row's "Mark unread" button, i.e. the chapter is read. If that
# deadline has already passed it still polls 1 s ("is it read now?").
# The chapter label is one line of the row as `tree` shows it, e.g. "Ch. 450".
# Writes the real /kartka RTDB as one persistent device (approved).
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f3
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly POLL_SEC=10

open_sync_screen() {
  pop_to_tabs
  check drive tap More >/dev/null
  drive wait "Sync now" --timeout 1 >/dev/null 2>&1 && return 0
  check drive wait "Sync" --timeout 5 >/dev/null
  check drive tap "Sync" >/dev/null
  check drive wait "Sync now" --timeout 5 >/dev/null
}

signed_in() {
  drive wait "Account (sign out)" --timeout "$1" >/dev/null 2>&1
}

sign_in() {
  step "start the agent instance"
  check "$AGENT" start >/dev/null

  step "open More -> Sync"
  open_sync_screen
  if signed_in 2; then
    echo "[f3] already signed in; skipping sign-in"
    return 0
  fi

  step "a seeded session exists"
  [[ -r "$AGENT_SEED" ]] ||
    fail "no seeded session at $AGENT_SEED. kuhy: run $SEED_CMD"

  # The wrapper reads the seed at start and serves it once per launch, so
  # restart both units: a fresh wrapper serves it, a fresh page adopts it.
  step "restart the agent so the wrapper serves the seed"
  check "$AGENT" stop >/dev/null
  check "$AGENT" start >/dev/null

  step "the Sync screen reads signed in (seed adopted)"
  open_sync_screen
  signed_in 15 || fail "seed at $AGENT_SEED not adopted. A build/web older \
than the seeded-session change never asks: rebuild it. Revoked or expired: \
reseed with $SEED_CMD. A profile that once signed out keeps an opt-out and \
never adopts: sign in on the Sync screen instead."
}

# Library root: tab, then pop any detail/reader pages left from earlier runs.
to_library_root() {
  pop_to_tabs
  check drive tap Library >/dev/null
  local i
  for ((i = 0; i < 4; i++)); do
    drive wait Back --timeout 1 >/dev/null 2>&1 || return 0
    check drive tap Back >/dev/null
  done
}

assert_read() {
  local title="$1" chapter="$2" trigger="${3:-$(date +%s)}"

  step "open \"$title\" from the Library"
  to_library_root
  check drive wait "$title" --timeout 10 >/dev/null
  check drive tap "$title" >/dev/null

  step "find chapter \"$chapter\" (scrolling the list)"
  local i
  for ((i = 0; i < 10; i++)); do
    drive wait "$chapter" --timeout 1 >/dev/null 2>&1 && break
    check drive scroll 0 600 >/dev/null
  done
  check drive wait "$chapter" --timeout 1 >/dev/null

  step "chapter shows as read by trigger + ${POLL_SEC} s"
  local left=$((trigger + POLL_SEC - $(date +%s)))
  ((left >= 1)) || left=1
  check drive wait "Mark unread" --row "$chapter" --timeout "$left"
}

main() {
  sign_in
  if (($# >= 2)); then
    assert_read "$@"
  fi
  echo "[f3] PASS"
}

main "$@"
