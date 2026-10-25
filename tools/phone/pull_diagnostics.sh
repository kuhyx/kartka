#!/bin/bash
# ============================================================================
# Pulls kartka's diagnostics log off the phone onto this PC.
#
# The release APK keeps it in the app-specific external files dir, which
# `adb pull` reads without root or run-as (lib/platform/platform.dart,
# KartkaPlatform.diagnostics; lib/core/diagnostics/diagnostics_log.dart).
# Read-only on the phone: never installs, clears or deletes anything.
#
# Usage: tools/phone/pull_diagnostics.sh
# Env:   ADB_SERIAL       device serial (default 23181JEGR08034)
#        KARTKA_DIAG_DEST where runs land (default
#                         ~/data/claude-scratch/kartka-diagnostics)
# Prints the pulled file's path. Exit 1: no device or no log yet.
# ============================================================================

set -euo pipefail

readonly ADB_SERIAL="${ADB_SERIAL:-23181JEGR08034}"
readonly DEST_ROOT="${KARTKA_DIAG_DEST:-$HOME/data/claude-scratch/kartka-diagnostics}"
readonly REMOTE='/sdcard/Android/data/com.kuhy.kartka/files/diagnostics/kartka-diagnostics.jsonl'

die() {
    echo "pull_diagnostics: $*" >&2
    exit 1
}

phone() { adb -s "$ADB_SERIAL" "$@"; }

main() {
    command -v adb >/dev/null || die "adb not found (pacman -S android-tools)"
    [[ "$(phone get-state 2>/dev/null || true)" == device ]] ||
        die "device $ADB_SERIAL not connected (adb devices)"
    # adb shell prints ls errors on stdout; "Permission denied" here would
    # mean this Android blocks adb from Android/data, not a missing log.
    local why
    why="$(phone shell ls "$REMOTE" 2>&1)" ||
        die "no log on the phone yet ($REMOTE): ${why:-not found}; kartka writes it on the first failure"
    local dest
    dest="$DEST_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$dest"
    phone pull "$REMOTE" "$dest/" >/dev/null || die "adb pull failed"
    local file="$dest/${REMOTE##*/}"
    [[ -s "$file" ]] || die "pulled an empty file: $file"
    echo "$file"
}

main "$@"
