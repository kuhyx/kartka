#!/bin/bash

# ============================================================================
# run.sh -- build and launch Kartka.
#
#   ./run.sh [desktop] [wrapper args]   web build + local wrapper + Chrome app
#                                       window (default). `--no-browser`
#                                       serves only (headless checks).
#   ./run.sh android                    arm64 release APK (scripts/
#                                       build_android.sh), `adb install -r`,
#                                       launch.
#                                       Never uninstalls (that wipes the
#                                       library); ANDROID_SERIAL picks a device.
#
# OAuth client ids are compile-time: when ~/.config/kartka/oauth.json exists
# scripts/build_web.sh passes it as --dart-define-from-file (build_android.sh
# encodes it the same way for the APK); never committed.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly APP_ID="com.kuhy.kartka"
readonly APK="${SCRIPT_DIR}/build/app/outputs/flutter-apk/app-release.apk"

log() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# fvm pins Flutter to .fvmrc; install it (and the pinned SDK) when missing.
ensure_fvm() {
    if ! command -v fvm >/dev/null 2>&1; then
        command -v yay >/dev/null 2>&1 || die "fvm missing and no yay to install it"
        log "installing fvm"
        yay -S --needed --noconfirm fvm
    fi
    (cd "${SCRIPT_DIR}" && fvm install --skip-pub-get >/dev/null)
}

ensure_adb() {
    command -v adb >/dev/null 2>&1 && return
    log "installing android-tools (adb)"
    sudo pacman -S --needed --noconfirm android-tools
}

run_desktop() {
    log "building the web bundle (stamped with its build, scripts/build_web.sh)"
    "${SCRIPT_DIR}/scripts/build_web.sh"
    log "starting the wrapper (it prints its URL)"
    cd "${SCRIPT_DIR}/desktop"
    fvm dart pub get >/dev/null
    exec fvm dart run bin/kartka_desktop.dart \
        --web-root "${SCRIPT_DIR}/build/web" "$@"
}

run_android() {
    ensure_adb
    cd "${SCRIPT_DIR}"
    # arm64 only, same props/defines as `flutter build apk`; capped agents run
    # its steps one call each (CLAUDE.md Commands).
    log "building the release APK (arm64)"
    scripts/build_android.sh release
    log "installing with adb install -r (data kept)"
    adb install -r "${APK}"
    adb shell monkey -p "${APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null
}

main() {
    ensure_fvm
    case "${1:-desktop}" in
        android) shift; run_android "$@" ;;
        desktop) [[ $# -gt 0 ]] && shift; run_desktop "$@" ;;
        -h|--help) sed -n '3,17p' "$0" ;;
        *) run_desktop "$@" ;;
    esac
}

main "$@"
