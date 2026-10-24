#!/bin/bash
# shellcheck disable=SC2034 # constants are read by the scripts that source this
# Shared helpers for tools/agent: paths of the ISOLATED agent instance and the
# step logger the flows use. Sourced, never run. The agent instance never
# touches kuhy's real app (port 47391, ~/.local/share/kartka-desktop/).

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AGENT_DIR
readonly REPO_DIR="${AGENT_DIR%/tools/agent}"
readonly UTILS_DIR="${KARTKA_UTILS_DIR:-$HOME/src/utils}"
readonly AGENT_PORT="${KARTKA_AGENT_PORT:-47392}"
readonly AGENT_CDP_PORT="${KARTKA_AGENT_CDP_PORT:-9342}"
readonly AGENT_HOME="$HOME/.local/share/kartka-agent"
readonly AGENT_URL="http://127.0.0.1:${AGENT_PORT}/"
readonly WRAPPER_UNIT="kartka-agent-wrapper"
readonly CHROME_UNIT="kartka-agent-chrome"
readonly FWD_APP_NAME="kartka-agent"

# Refuse the real app's port outright: its IndexedDB and OAuth redirect are
# keyed to it, and a second wrapper there would steal kuhy's session.
if [[ "$AGENT_PORT" == "47391" ]]; then
  echo "kartka-agent: refusing port 47391 (kuhy's real app)" >&2
  exit 2
fi

# drive <verb> [args...]: one flutter_web_drive call against the agent browser.
drive() {
  PYTHONPATH="$UTILS_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m flutter_web_drive --app "$FWD_APP_NAME" "$@"
}

# Flow step logging: `step "<what>"` before each step, `fail "<why>"` to abort
# with a screenshot path. FLOW must be set by the flow script.
STEP_NO=0
STEP_NAME=""
step() {
  STEP_NO=$((STEP_NO + 1))
  STEP_NAME="$1"
  echo "[${FLOW:-flow}] step ${STEP_NO}: ${STEP_NAME}"
}

fail() {
  local shot
  shot="$(drive shot 2>/dev/null | cut -d' ' -f1 || true)"
  echo "[${FLOW:-flow}] FAILED step ${STEP_NO} (${STEP_NAME}): $1" >&2
  echo "[${FLOW:-flow}] screenshot: ${shot:-<none: browser unreachable>}" >&2
  exit 1
}

# check <cmd...>: run a step command, fail the flow (with its stderr) if it fails.
check() {
  local out
  if ! out="$("$@" 2>&1)"; then
    fail "$(printf '%s' "$out" | tail -3)"
  fi
  printf '%s\n' "$out"
}

# Pop pushed full-screen routes (sign-in form, reader) until the tab rail shows.
pop_to_tabs() {
  local i
  for ((i = 0; i < 4; i++)); do
    drive wait "Tab 4 of 4" --contains --timeout 1 >/dev/null 2>&1 && return 0
    check drive tap Back >/dev/null
  done
  check drive wait "Tab 4 of 4" --contains --timeout 2 >/dev/null
}
