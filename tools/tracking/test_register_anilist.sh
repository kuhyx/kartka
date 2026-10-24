#!/bin/bash
# ============================================================================
# Offline test for register_anilist.sh: xdg-open, xclip and curl are stubs on
# PATH, HOME is a temp dir, Enter presses come from stdin. Opens no window.
# Run: tools/tracking/test_register_anilist.sh
# ============================================================================

set -euo pipefail
export KARTKA_OPEN_URL_SYNC=1

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
readonly SCRIPT="$HERE/register_anilist.sh"
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
    cat >"$SANDBOX/bin/curl" <<'EOF'
#!/bin/bash
if [[ " $* " == *"Bearer GOODTOKEN"* ]]; then
  echo '{"data":{"Viewer":{"id":1,"name":"kuhy"}}}'
else
  echo '{"data":null,"errors":[{"message":"Invalid token","status":400}]}'
fi
EOF
    chmod +x "$SANDBOX/bin/"*
}

# Runs the script with stubs; $1 = clipboard queue, rest = script args.
run_script() {
    local queue="$1"
    shift
    printf '%s\n' "$queue" >"$SANDBOX/clip_queue"
    : >"$SANDBOX/clip_log"
    : >"$SANDBOX/opened"
    printf '\n%.0s' {1..40} |
        PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" STUB_DIR="$SANDBOX" \
            "$SCRIPT" "$@" >"$SANDBOX/out" 2>&1
}

conf() { echo "$SANDBOX/home/.config/kartka/oauth.json"; }

test_full_registration() {
    mkdir -p "$SANDBOX/home/.config/kartka"
    echo '{"KARTKA_MAL_CLIENT_ID":"keepme"}' >"$(conf)"
    local login='http://127.0.0.1:47391/oauth#access_token=GOODTOKEN&token_type=Bearer&expires_in=31536000'
    run_script $'not-an-id\n11111\n22222\n'"$login" ||
        fail "registration exited non-zero: $(cat "$SANDBOX/out")"
    [[ "$(jq -r .KARTKA_ANILIST_CLIENT_ID_ANDROID "$(conf)")" == 11111 ]] ||
        fail "android id not stored"
    [[ "$(jq -r .KARTKA_ANILIST_CLIENT_ID_WEB "$(conf)")" == 22222 ]] ||
        fail "web id not stored"
    [[ "$(jq -r .KARTKA_MAL_CLIENT_ID "$(conf)")" == keepme ]] ||
        fail "existing MAL key lost"
    [[ "$(stat -c %a "$(conf)")" == 600 ]] || fail "config mode not 600"
    local want=$'Kartka Android\nkartka://oauth\nKartka Web\nhttp://127.0.0.1:47391/oauth'
    [[ "$(grep -v '^$' "$SANDBOX/clip_log")" == "$want" ]] ||
        fail "clipboard order: $(cat "$SANDBOX/clip_log")"
    grep -q 'anilist.co/settings/developer' "$SANDBOX/opened" ||
        fail "developer page not opened"
    grep -q 'client_id=22222&response_type=token' "$SANDBOX/opened" ||
        fail "web login not opened"
    grep -q 'logged in as kuhy' "$SANDBOX/out" || fail "no login confirmation"
}

test_verify_only_bad_token() {
    run_script 'http://127.0.0.1:47391/oauth#access_token=BAD' --verify-only &&
        fail "bad token passed verification"
    grep -q 'Invalid token' "$SANDBOX/out" || fail "bad token reason missing"
}

test_verify_only_wrong_redirect() {
    run_script 'http://localhost:9999/x#access_token=GOODTOKEN' --verify-only &&
        fail "wrong redirect passed verification"
    grep -q 'redirect' "$SANDBOX/out" || fail "redirect reason missing"
}

test_verify_only_mode() {
    chmod 644 "$(conf)"
    run_script '' --verify-only --no-login && fail "mode 644 passed"
    chmod 600 "$(conf)"
    run_script '' --verify-only --no-login ||
        fail "--no-login verify failed: $(cat "$SANDBOX/out")"
    [[ ! -s "$SANDBOX/opened" ]] || fail "--no-login opened a page"
}

test_verify_only_missing_key() {
    jq 'del(.KARTKA_ANILIST_CLIENT_ID_WEB)' "$(conf)" >"$SANDBOX/c" &&
        cat "$SANDBOX/c" >"$(conf)"
    run_script '' --verify-only --no-login && fail "missing web id passed"
    grep -q 'KARTKA_ANILIST_CLIENT_ID_WEB' "$SANDBOX/out" ||
        fail "missing key not named"
}

main() {
    SANDBOX="$(mktemp -d)"
    make_stubs
    test_full_registration
    test_verify_only_bad_token
    test_verify_only_wrong_redirect
    test_verify_only_mode
    test_verify_only_missing_key
    if [[ "$FAILS" -gt 0 ]]; then
        echo "$FAILS check(s) failed"
        exit 1
    fi
    echo "register_anilist.sh: all checks passed"
}

main "$@"
