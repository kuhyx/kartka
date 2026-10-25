#!/bin/bash
# ============================================================================
# Offline test for pull_diagnostics.sh: adb is a stub on PATH that fakes a
# phone, results land in a temp dir. Touches no phone.
# Run: tools/phone/test_pull_diagnostics.sh
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
readonly SCRIPT="$HERE/pull_diagnostics.sh"
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

# A stub adb: STUB_STATE is get-state's answer, STUB_LOG the phone's file
# (absent = no log yet). Every call is appended to $STUB_DIR/calls.
make_stub() {
    mkdir -p "$SANDBOX/bin"
    cat >"$SANDBOX/bin/adb" <<'EOF'
#!/bin/bash
echo "$*" >>"$STUB_DIR/calls"
shift 2
case "$1" in
    get-state) echo "$STUB_STATE" ;;
    shell) [[ -f "$STUB_DIR/phone.jsonl" ]] ;;
    pull) cp "$STUB_DIR/phone.jsonl" "$3$(basename "$2")" ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/adb"
}

# Runs the script in a fresh sandbox; prints stdout, returns its status.
run_script() {
    PATH="$SANDBOX/bin:$PATH" STUB_DIR="$SANDBOX" STUB_STATE="${1:-device}" \
        KARTKA_DIAG_DEST="$SANDBOX/out" ADB_SERIAL="${ADB_SERIAL_TEST:-}" \
        "$SCRIPT" 2>"$SANDBOX/stderr"
}

setup() {
    cleanup
    SANDBOX="$(mktemp -d)"
    make_stub
}

test_pulls_into_a_timestamped_dir() {
    setup
    echo '{"kind":"reader.advance"}' >"$SANDBOX/phone.jsonl"
    local out
    out="$(ADB_SERIAL_TEST=SER1 run_script)" || fail "pull exited non-zero"
    [[ "$out" =~ ^$SANDBOX/out/[0-9]{8}T[0-9]{6}Z/kartka-diagnostics.jsonl$ ]] ||
        fail "unexpected path: $out"
    grep -q reader.advance "$out" || fail "pulled file lacks the entry"
    grep -q '^-s SER1 pull /sdcard/Android/data/com.kuhy.kartka/files/diagnostics/kartka-diagnostics.jsonl' \
        "$SANDBOX/calls" || fail "wrong serial or remote path"
}

test_default_serial() {
    setup
    echo x >"$SANDBOX/phone.jsonl"
    run_script >/dev/null || fail "default serial run failed"
    grep -q '^-s 23181JEGR08034 get-state' "$SANDBOX/calls" ||
        fail "default serial not used"
}

test_no_device() {
    setup
    if run_script offline >/dev/null; then fail "no device should fail"; fi
    grep -q "not connected" "$SANDBOX/stderr" || fail "no device message"
    [[ ! -d "$SANDBOX/out" ]] || fail "created a dir without a device"
}

test_no_log_yet() {
    setup
    if run_script >/dev/null; then fail "missing log should fail"; fi
    grep -q "no log on the phone yet" "$SANDBOX/stderr" || fail "no-log message"
    grep -q " pull " "$SANDBOX/calls" && fail "pulled a missing file"
    return 0
}

main() {
    test_pulls_into_a_timestamped_dir
    test_default_serial
    test_no_device
    test_no_log_yet
    if ((FAILS > 0)); then
        echo "$FAILS check(s) failed"
        exit 1
    fi
    echo "pull_diagnostics: all checks passed"
}

main "$@"
