#!/bin/bash
# f3 sync: sign the agent instance into the shared sync account (password
# sign-in, idempotent), then optionally assert a chapter shows as read.
#
#   tools/agent/flows/f3_sync.sh                                  # sign in only
#   tools/agent/flows/f3_sync.sh "<manga title>" "<chapter label>" [trigger_epoch]
#
# The assert polls until trigger_epoch + 10 s (default: now + 10 s) for the
# chapter row's "Mark unread" button, i.e. the chapter is read. If that
# deadline has already passed it still polls 1 s ("is it read now?").
# The chapter label is one line of the row as `tree` shows it, e.g. "Ch. 450". Writes the
# real /kartka RTDB as one persistent device (approved). Credentials come from
# ~/.config/crdt-sync/ and are piped, never printed or put in argv.
set -euo pipefail

# shellcheck disable=SC2034 # read by lib.sh
FLOW=f3
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
readonly AGENT="$AGENT_DIR/kartka_agent.sh"
readonly CRED_DIR="$HOME/.config/crdt-sync"
readonly POLL_SEC=10

open_sync_screen() {
  pop_to_tabs
  check drive tap More >/dev/null
  drive wait "Sync now" --timeout 1 >/dev/null 2>&1 && return 0
  check drive wait "Sync" --timeout 5 >/dev/null
  check drive tap "Sync" >/dev/null
  check drive wait "Sync now" --timeout 5 >/dev/null
}

sign_in() {
  step "start the agent instance"
  check "$AGENT" start >/dev/null

  step "open More -> Sync"
  open_sync_screen
  if drive wait "Account (sign out)" --timeout 2 >/dev/null 2>&1; then
    echo "[f3] already signed in; skipping sign-in"
    return 0
  fi

  step "open the password sign-in form"
  [[ -r "$CRED_DIR/password" && -r "$CRED_DIR/firebase.json" ]] ||
    fail "credentials missing in $CRED_DIR"
  check drive tap "Sign in" >/dev/null
  check drive wait "Use the account password instead" --timeout 5 >/dev/null
  check drive tap "Use the account password instead" >/dev/null
  check drive wait "Sync account email" --timeout 5 >/dev/null

  step "enter the email (from firebase.json) and password (piped from file)"
  check drive tap "Sync account email" >/dev/null
  jq -er '.email' "$CRED_DIR/firebase.json" | check drive text --stdin
  check drive tap "Sync account password" >/dev/null
  check drive text --file "$CRED_DIR/password"

  step "connect and wait for the session"
  check drive tap "Connect Firebase" >/dev/null
  local i msg
  for ((i = 0; i < 20; i++)); do
    drive wait "Disconnect" --timeout 1 >/dev/null 2>&1 && break
    msg="$(drive tree --filter "rejected" 2>/dev/null || true)"
    if [[ -n "$msg" && "$msg" != "(no matching"* ]]; then
      drive tap Back >/dev/null 2>&1 || true # drop the typed form
      fail "Firebase refused the sign-in: $(cut -d'"' -f2 <<<"$msg")"
    fi
  done
  check drive wait "Disconnect" --timeout 1

  step "back on the Sync screen it reads signed in"
  check drive tap "Back" >/dev/null
  check drive wait "Account (sign out)" --timeout 10
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
