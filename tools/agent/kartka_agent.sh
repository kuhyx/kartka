#!/bin/bash
# Headless agent instance of the Kartka desktop app, for LLM-driven E2E checks
# that never touch kuhy's screen, mouse, keyboard or his real app.
#
#   kartka_agent.sh start     # isolated wrapper (port 47392) + headless chromium
#   kartka_agent.sh stop      # stop both units (data and profile kept)
#   kartka_agent.sh status
#   kartka_agent.sh fault <host|*> <mode>   # inject a /proxy fault: offline,
#                             # abort-once, page-500, webview, upstream-dns, gone,
#                             # slow-pages[:<ms>], slow-details[:<ms>]
#   kartka_agent.sh fault clear             # back to the real network
#   kartka_agent.sh <verb>    # any flutter_web_drive verb: tree, tap, text,
#                             # key, scroll, wait, shot, eval, console, tap-xy
#
# Both run as `systemd-run --user` units so they outlive the calling shell.
# Agent data lives in ~/.local/share/kartka-agent/{files,secrets.json,profile};
# the real app's port 47391 and ~/.local/share/kartka-desktop/ are never used.
# With ~/.config/kartka-agent/firebase_auth.json present the wrapper serves
# it once as /sync-credentials, which signs the app in (lib.sh: AGENT_SEED).
# Serves the existing build/web; rebuild it separately with:
#   ~/.claude/scripts/capped.sh fvm flutter build web --release \
#     --dart-define-from-file="$HOME/.config/kartka/oauth.json"
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly WRAPPER_WAIT_SEC=30

port_open() {
  curl -s -o /dev/null --max-time 1 "$AGENT_URL"
}

# The wrapper runs as a compiled exe, never `fvm dart run`: through the
# board's fvm shim a `dart run` server holds a machine-wide build slot for as
# long as it serves. The exe is rebuilt (about 2 s) only when a wrapper source
# is newer than it.
readonly WRAPPER_EXE="$REPO_DIR/desktop/.dart_tool/kartka_desktop"

wrapper_exe() {
  local stale
  stale="$(find "$REPO_DIR/desktop/bin" "$REPO_DIR/desktop/lib" \
    "$REPO_DIR/desktop/pubspec.yaml" "$REPO_DIR/desktop/pubspec.lock" \
    -type f -newer "$WRAPPER_EXE" -print -quit 2>/dev/null || true)"
  [[ -x "$WRAPPER_EXE" && -z "$stale" ]] && return 0
  (cd "$REPO_DIR/desktop" && fvm dart pub get >/dev/null &&
    fvm dart compile exe bin/kartka_desktop.dart -o "$WRAPPER_EXE" >/dev/null)
}

start_wrapper() {
  if port_open; then
    return 0
  fi
  if ! systemctl --user is-active --quiet "$WRAPPER_UNIT"; then
    [[ -f "$REPO_DIR/build/web/index.html" ]] ||
      { echo "kartka-agent: no build/web; build it first (see header)" >&2; exit 1; }
    mkdir -p "$AGENT_HOME/files"
    # Only the agent wrapper ever gets the seed; read at wrapper start, so a
    # seed written later needs `stop` + `start`.
    local seed=()
    [[ -r "$AGENT_SEED" ]] && seed=(--sync-credentials "$AGENT_SEED")
    wrapper_exe
    systemctl --user reset-failed "$WRAPPER_UNIT" 2>/dev/null || true
    systemd-run --user --unit="$WRAPPER_UNIT" --collect --quiet \
      -p WorkingDirectory="$REPO_DIR/desktop" \
      -p "UnsetEnvironment=DISPLAY WAYLAND_DISPLAY" \
      "$WRAPPER_EXE" \
      --web-root "$REPO_DIR/build/web" --no-browser --port "$AGENT_PORT" \
      --files-dir "$AGENT_HOME/files" --secrets-path "$AGENT_HOME/secrets.json" \
      --fault-file "$AGENT_FAULTS" --agent "${seed[@]}"
  fi
  # Poll until it serves; if it is still not up, tell the caller to rerun
  # rather than blocking past the 60 s action cap.
  local i
  for ((i = 0; i < WRAPPER_WAIT_SEC * 4; i++)); do
    port_open && return 0
    systemctl --user is-active --quiet "$WRAPPER_UNIT" ||
      { echo "kartka-agent: wrapper exited; journalctl --user -u $WRAPPER_UNIT" >&2; exit 3; }
    sleep 0.25
  done
  echo "kartka-agent: wrapper not serving yet; rerun start" >&2
  exit 3
}

cmd_start() {
  start_wrapper
  echo "wrapper: $AGENT_URL (unit $WRAPPER_UNIT)"
  drive start --url "$AGENT_URL" --profile "$AGENT_HOME/profile" \
    --cdp-port "$AGENT_CDP_PORT" --unit "$CHROME_UNIT"
}

cmd_stop() {
  drive stop || true
  systemctl --user stop "$WRAPPER_UNIT" 2>/dev/null || true
  echo "stopped $WRAPPER_UNIT"
}

cmd_status() {
  local unit
  for unit in "$WRAPPER_UNIT" "$CHROME_UNIT"; do
    printf '%s: %s\n' "$unit" "$(systemctl --user is-active "$unit" 2>/dev/null || true)"
  done
}

# Writes the wrapper's fault rules (desktop/lib/src/faults.dart); it rereads
# them per request, so no restart. `clear` removes every rule.
cmd_fault() {
  local host="${1:-}" mode="${2:-}"
  mkdir -p "$AGENT_HOME"
  if [[ "$host" == clear ]]; then
    rm -f "$AGENT_FAULTS"
    echo "faults: none"
    return 0
  fi
  [[ -n "$host" && -n "$mode" ]] ||
    { echo "usage: kartka_agent.sh fault <host|*> <mode> | clear" >&2; exit 2; }
  local current='{}'
  [[ -r "$AGENT_FAULTS" ]] && current="$(cat "$AGENT_FAULTS")"
  jq --arg h "$host" --arg m "$mode" '.[$h] = $m' <<<"$current" >"$AGENT_FAULTS.tmp"
  mv "$AGENT_FAULTS.tmp" "$AGENT_FAULTS"
  echo "faults: $(jq -c . "$AGENT_FAULTS")"
}

main() {
  local verb="${1:-}"
  case "$verb" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    fault) shift; cmd_fault "$@" ;;
    "" | -h | --help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) drive "$@" ;;
  esac
}

main "$@"
