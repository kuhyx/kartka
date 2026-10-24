#!/bin/bash
# ============================================================================
# Offline test for register_google_signin.sh: xdg-open, xclip, curl, keytool
# and adb are stubs on PATH, HOME is a temp dir, Enter presses come from
# stdin. Opens no window, touches no phone or console.
# Run: tools/sync/test_register_google_signin.sh
# ============================================================================

set -euo pipefail
export KARTKA_OPEN_URL_SYNC=1

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
readonly SCRIPT="$HERE/register_google_signin.sh"
readonly SHA='D5:08:AB:C0:86:49:56:53:CD:07:06:31:77:EE:B8:12:EF:4E:5C:4B'
readonly ANDROID_ID='845446124781-abc123def456.apps.googleusercontent.com'
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
    mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.android"
    : >"$SANDBOX/home/.android/debug.keystore"
    cat >"$SANDBOX/bin/xdg-open" <<'EOF'
#!/bin/bash
echo "$1" >>"$STUB_DIR/opened"
EOF
    cat >"$SANDBOX/bin/xclip" <<'EOF'
#!/bin/bash
if [[ " $* " == *" -in "* ]]; then cat >>"$STUB_DIR/clip_log"; echo >>"$STUB_DIR/clip_log"; exit 0; fi
cat "$STUB_DIR/clip_out"
EOF
    cat >"$SANDBOX/bin/keytool" <<EOF
#!/bin/bash
printf '\t SHA1: %s\n\t SHA256: AA\n' '$SHA'
EOF
    # checkOrigin answers valid once $STUB_DIR/origin_ok exists.
    cat >"$SANDBOX/bin/curl" <<'EOF'
#!/bin/bash
[[ " $* " == *"origin=http%3A//127.0.0.1%3A47391"* ]] || { echo '{}'; exit 0; }
if [[ -f "$STUB_DIR/origin_ok" ]]; then echo '{"valid":true}'; else echo '{"valid":false}'; fi
EOF
    cat >"$SANDBOX/bin/adb" <<'EOF'
#!/bin/bash
case "$*" in
  devices) printf 'List of devices attached\n23181JEGR08034\tdevice\n' ;;
  *" pull "*) cp "$STUB_DIR/screen" "${@: -1}" ;;
esac
EOF
    chmod +x "$SANDBOX/bin/"*
    printf '%s\n' 'plain text' 'signingConfig = signingConfigs.getByName("debug")' \
        >"$SANDBOX/gradle"
}

# Runs the script with stubs; arguments pass through.
run_script() {
    : >"$SANDBOX/clip_log"
    : >"$SANDBOX/opened"
    printf '\n%.0s' {1..20} |
        env -u KARTKA_CONFIG_DIR -u KARTKA_OAUTH_FILE \
            PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
            KARTKA_GRADLE="${GRADLE_FILE:-$SANDBOX/gradle}" \
            KARTKA_APK=/nonexistent KARTKA_VERIFY_TRIES=2 KARTKA_VERIFY_PAUSE=0 \
            STUB_DIR="$SANDBOX" \
            "$SCRIPT" "$@" >"$SANDBOX/out" 2>&1
}

conf() { echo "$SANDBOX/home/.config/kartka/oauth.json"; }

test_sha1_from_release_keystore() {
    run_script --sha1 || fail "--sha1 exited non-zero: $(cat "$SANDBOX/out")"
    [[ "$(cat "$SANDBOX/out")" == "$SHA" ]] || fail "sha1: $(cat "$SANDBOX/out")"
    echo 'signingConfig = signingConfigs.getByName("release")' >"$SANDBOX/other"
    GRADLE_FILE="$SANDBOX/other" run_script --sha1 && fail "a non-debug signer passed"
    grep -q 'no longer signed with the debug key' "$SANDBOX/out" ||
        fail "signer-change reason missing"
}

test_full_registration() {
    printf '%s' "$ANDROID_ID" >"$SANDBOX/clip_out"
    echo 'Disconnect' >"$SANDBOX/screen"
    rm -f "$SANDBOX/origin_ok"
    run_script && fail "an unregistered origin verified"
    local want=$'kartka\ncom.kuhy.kartka\n'"$SHA"$'\nhttp://127.0.0.1:47391'
    [[ "$(cat "$SANDBOX/clip_log" | sed '/^$/d')" == "$want" ]] ||
        fail "clipboard order: $(cat "$SANDBOX/clip_log")"
    [[ "$(jq -r .KARTKA_GOOGLE_CLIENT_ID_ANDROID "$(conf)")" == "$ANDROID_ID" ]] ||
        fail "android client id not stored"
    [[ "$(stat -c %a "$(conf)")" == 600 ]] || fail "config mode not 600"
    grep -q 'auth/clients?project=kuhy-syncs' "$SANDBOX/opened" ||
        fail "clients page not opened"
    grep -q 'FAIL web' "$SANDBOX/out" || fail "web failure not reported"
    grep -q 'OK   android' "$SANDBOX/out" || fail "android not verified"
}

test_bad_clipboard_id_not_stored() {
    rm -f "$(conf)"
    printf 'junk' >"$SANDBOX/clip_out"
    touch "$SANDBOX/origin_ok"
    run_script || fail "registration failed: $(cat "$SANDBOX/out")"
    [[ ! -f "$(conf)" ]] || fail "a junk client id was stored"
    grep -q 'already allowed' "$SANDBOX/out" || fail "allowed origin re-added"
}

test_verify_only() {
    touch "$SANDBOX/origin_ok"
    echo 'Google sign-in was cancelled. Disconnect' >"$SANDBOX/screen"
    run_script --verify-only && fail "a cancelled sign-in verified"
    echo 'Disconnect' >"$SANDBOX/screen"
    run_script --verify-only || fail "verify failed: $(cat "$SANDBOX/out")"
    [[ ! -s "$SANDBOX/opened" ]] || fail "--verify-only opened a page"
}

main() {
    SANDBOX="$(mktemp -d)"
    make_stubs
    test_sha1_from_release_keystore
    test_full_registration
    test_bad_clipboard_id_not_stored
    test_verify_only
    if [[ "$FAILS" -gt 0 ]]; then
        echo "$FAILS check(s) failed"
        exit 1
    fi
    echo "register_google_signin.sh: all checks passed"
}

main "$@"
