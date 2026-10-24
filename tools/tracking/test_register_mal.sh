#!/bin/bash
# ============================================================================
# Offline test for register_mal.sh: xdg-open, xclip and curl are stubs on
# PATH, HOME is a temp dir, Enter presses come from stdin. Opens no window.
# Run: tools/tracking/test_register_mal.sh
# ============================================================================

set -euo pipefail
export KARTKA_OPEN_URL_SYNC=1

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
readonly SCRIPT="$HERE/register_mal.sh"
readonly ANDROID_ID='aaaaaaaaaaaaaaaaaaaaaaaaaaaa1111'
readonly WEB_ID='bbbbbbbbbbbbbbbbbbbbbbbbbbbb2222'
SANDBOX=""
FAILS=0

cleanup() {
    if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then rm -rf "$SANDBOX"; fi
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

# Writes the stub tools into $SANDBOX/bin.
make_stubs() {
    mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
    cat >"$SANDBOX/bin/xdg-open" <<'EOF'
#!/bin/bash
echo "$1" >>"$STUB_DIR/opened"
EOF
    # -in appends to clip_log; -out pops the next line of clip_queue.
    cat >"$SANDBOX/bin/xclip" <<'EOF'
#!/bin/bash
if [[ " $* " == *" -in "* ]]; then cat >>"$STUB_DIR/clip_log"; echo >>"$STUB_DIR/clip_log"; exit 0; fi
head -n 1 "$STUB_DIR/clip_queue"
sed -i 1d "$STUB_DIR/clip_queue"
EOF
    # The script asks only for the HTTP status; known ids get 200.
    cat >"$SANDBOX/bin/curl" <<'EOF'
#!/bin/bash
if [[ " $* " == *"X-MAL-CLIENT-ID: aaaaaaaaaaaaaaaaaaaaaaaaaaaa1111"* ||
      " $* " == *"X-MAL-CLIENT-ID: bbbbbbbbbbbbbbbbbbbbbbbbbbbb2222"* ]]; then
  printf 200
else
  printf 401
fi
EOF
    chmod +x "$SANDBOX/bin/"*
}

# Runs the script with stubs; $1 = clipboard queue, rest = script args.
# Every config-location variable points into the sandbox, so a run can never
# touch the real ~/.config/kartka/oauth.json.
run_script() {
    local queue="$1"
    shift
    printf '%s\n' "$queue" >"$SANDBOX/clip_queue"
    : >"$SANDBOX/clip_log"
    : >"$SANDBOX/opened"
    printf '\n%.0s' {1..60} |
        env -u KARTKA_CONFIG_DIR -u KARTKA_OAUTH_FILE \
            PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
            XDG_CONFIG_HOME="$SANDBOX/home/.config" STUB_DIR="$SANDBOX" \
            "$SCRIPT" "$@" >"$SANDBOX/out" 2>&1
}

conf() { echo "$SANDBOX/home/.config/kartka/oauth.json"; }

test_sources_common() {
    grep -qE '^source .*/oauth_common\.sh"$' "$SCRIPT" ||
        fail "does not source oauth_common.sh"
    if grep -qE '^(die|ensure_tools|clip_put|clip_get|config_[a-z_]+)\(\)' "$SCRIPT"; then
        fail "redefines a helper from oauth_common.sh"
    fi
}

test_full_registration() {
    mkdir -p "$SANDBOX/home/.config/kartka"
    echo '{"KARTKA_ANILIST_CLIENT_ID_WEB":"keepme"}' >"$(conf)"
    run_script "${ANDROID_ID}"$'\n'"${WEB_ID}" ||
        fail "registration exited non-zero: $(cat "$SANDBOX/out")"
    [[ "$(jq -r .KARTKA_MAL_CLIENT_ID_ANDROID "$(conf)")" == "$ANDROID_ID" ]] ||
        fail "android id not stored"
    [[ "$(jq -r .KARTKA_MAL_CLIENT_ID_WEB "$(conf)")" == "$WEB_ID" ]] ||
        fail "web id not stored"
    [[ "$(jq -r .KARTKA_ANILIST_CLIENT_ID_WEB "$(conf)")" == keepme ]] ||
        fail "existing AniList key lost"
    [[ "$(stat -c %a "$(conf)")" == 600 ]] || fail "config mode not 600"
    local want=$'kartka://oauth\nhttp://127.0.0.1:47391/oauth'
    [[ "$(grep -E '^(kartka|http://127)' "$SANDBOX/clip_log")" == "$want" ]] ||
        fail "redirects on clipboard: $(cat "$SANDBOX/clip_log")"
    [[ "$(grep -c 'apiconfig/create' "$SANDBOX/opened")" == 2 ]] ||
        fail "create page not opened twice"
    grep -q 'OK   web' "$SANDBOX/out" || fail "web id not verified"
}

test_bad_clipboard_id() {
    run_script 'short' --only android && fail "a short id was accepted"
    grep -q 'does not look like a client id' "$SANDBOX/out" ||
        fail "bad id reason missing"
}

test_verify_only_rejected_id() {
    jq '.KARTKA_MAL_CLIENT_ID_WEB = "cccccccccccccccccccccccccccc3333"' "$(conf)" >"$SANDBOX/c" &&
        cat "$SANDBOX/c" >"$(conf)"
    run_script '' --verify-only && fail "rejected id passed verification"
    grep -q 'FAIL web: MAL answered HTTP 401' "$SANDBOX/out" ||
        fail "rejection reason missing"
}

test_verify_only_mode() {
    jq --arg v "$WEB_ID" '.KARTKA_MAL_CLIENT_ID_WEB = $v' "$(conf)" >"$SANDBOX/c" &&
        cat "$SANDBOX/c" >"$(conf)"
    chmod 644 "$(conf)"
    run_script '' --verify-only && fail "mode 644 passed"
    chmod 600 "$(conf)"
    run_script '' --verify-only || fail "verify failed: $(cat "$SANDBOX/out")"
    [[ ! -s "$SANDBOX/opened" ]] || fail "--verify-only opened a page"
}

main() {
    SANDBOX="$(mktemp -d)"
    make_stubs
    test_sources_common
    test_full_registration
    test_bad_clipboard_id
    test_verify_only_rejected_id
    test_verify_only_mode
    if [[ "$FAILS" -gt 0 ]]; then
        echo "$FAILS check(s) failed"
        exit 1
    fi
    echo "register_mal.sh: all checks passed"
}

main "$@"
