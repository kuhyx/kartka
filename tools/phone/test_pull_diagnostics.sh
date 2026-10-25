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

# A stub adb: STUB_STATE is get-state's answer, $STUB_DIR/files/ is the
# phone's app files dir (a missing path answers like a locked one does).
# Every call is appended to $STUB_DIR/calls.
make_stub() {
    mkdir -p "$SANDBOX/bin"
    cat >"$SANDBOX/bin/adb" <<'EOF'
#!/bin/bash
echo "$*" >>"$STUB_DIR/calls"
shift 2
readonly PHONE_FILES=/sdcard/Android/data/com.kuhy.kartka/files
local_path() { echo "$STUB_DIR/files${1#"$PHONE_FILES"}"; }
case "$1" in
    get-state) echo "$STUB_STATE" ;;
    shell)
        [[ "$2" == ls ]] || exit 2
        path="$(local_path "$3")"
        [[ -e "$path" ]] || { echo "ls: $3: Permission denied"; exit 1; }
        ls "$path"
        ;;
    pull) cp -r "$(local_path "$2")" "$3" ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/adb"
}

# Puts $1 into the fake phone's diagnostics log.
phone_log() {
    mkdir -p "$SANDBOX/files/diagnostics"
    echo "$1" >"$SANDBOX/files/diagnostics/kartka-diagnostics.jsonl"
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
    phone_log '{"kind":"reader.advance"}'
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
    phone_log x
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
    grep -q "Permission denied" "$SANDBOX/stderr" || fail "adb's reason dropped"
    grep -q " pull " "$SANDBOX/calls" && fail "pulled a missing file"
    return 0
}

# Migration backups (lib/migration/migration_backup.dart) sit in files/backups/.
test_pulls_backups() {
    setup
    phone_log x
    mkdir -p "$SANDBOX/files/backups"
    echo '{"a":1}' >"$SANDBOX/files/backups/kartka-backup-20261001T000000Z.json"
    echo '{"b":2}' >"$SANDBOX/files/backups/kartka-backup-20261002T000000Z.json"
    local out
    out="$(run_script)" || fail "backups run exited non-zero"
    local dir="${out%/*}/backups"
    grep -qs '"a":1' "$dir/kartka-backup-20261001T000000Z.json" ||
        fail "first backup not pulled into $dir"
    grep -qs '"b":2' "$dir/kartka-backup-20261002T000000Z.json" ||
        fail "second backup not pulled into $dir"
    grep -q '^-s 23181JEGR08034 pull /sdcard/Android/data/com.kuhy.kartka/files/backups ' \
        "$SANDBOX/calls" || fail "backups pulled from the wrong remote path"
    [[ "$(wc -l <<<"$out")" -eq 1 ]] || fail "stdout is not just the log path: $out"
}

test_no_backups_dir() {
    setup
    phone_log x
    local out
    out="$(run_script)" || fail "missing backups/ should not fail"
    [[ ! -e "${out%/*}/backups" ]] || fail "made backups/ with none on the phone"
    grep -q 'files/backups' "$SANDBOX/calls" || fail "never looked for backups/"
    grep -q ' pull .*files/backups' "$SANDBOX/calls" && fail "pulled a missing backups/"
    return 0
}

test_empty_backups_dir() {
    setup
    phone_log x
    mkdir -p "$SANDBOX/files/backups"
    run_script >/dev/null || fail "empty backups/ should not fail"
    grep -q ' pull .*files/backups' "$SANDBOX/calls" && fail "pulled an empty backups/"
    return 0
}

main() {
    test_pulls_into_a_timestamped_dir
    test_default_serial
    test_no_device
    test_no_log_yet
    test_pulls_backups
    test_no_backups_dir
    test_empty_backups_dir
    if ((FAILS > 0)); then
        echo "$FAILS check(s) failed"
        exit 1
    fi
    echo "pull_diagnostics: all checks passed"
}

main "$@"
