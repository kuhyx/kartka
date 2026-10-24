#!/bin/bash

# ============================================================================
# run.sh -- build and launch Kartka.
#
#   ./run.sh [desktop] [wrapper args]   web build + local wrapper + Chrome app
#                                       window (default). `--no-browser`
#                                       serves only (headless checks).
#   ./run.sh android                    release APK, `adb install -r`, launch.
#                                       Never uninstalls (that wipes the
#                                       library); ANDROID_SERIAL picks a device.
#
# OAuth client ids are compile-time: when ~/.config/kartka/oauth.json exists
# it is passed as --dart-define-from-file to both builds (never committed).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly OAUTH_DEFINES="${HOME}/.config/kartka/oauth.json"
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

# Prints the --dart-define-from-file flag when the OAuth defines exist.
define_args() {
    if [[ -f "${OAUTH_DEFINES}" ]]; then
        printf -- '--dart-define-from-file=%s\n' "${OAUTH_DEFINES}"
    fi
}

run_desktop() {
    local -a defines
    mapfile -t defines < <(define_args)
    cd "${SCRIPT_DIR}"
    log "building the web bundle"
    fvm flutter build web --release "${defines[@]}"
    log "starting the wrapper (it prints its URL)"
    cd "${SCRIPT_DIR}/desktop"
    fvm dart pub get >/dev/null
    exec fvm dart run bin/kartka_desktop.dart \
        --web-root "${SCRIPT_DIR}/build/web" "$@"
}

run_android() {
    local -a defines
    mapfile -t defines < <(define_args)
    ensure_adb
    cd "${SCRIPT_DIR}"
    log "building the release APK"
    fvm flutter build apk --release "${defines[@]}"
    log "installing with adb install -r (data kept)"
    adb install -r "${APK}"
    adb shell monkey -p "${APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null
}

main() {
    ensure_fvm
    case "${1:-desktop}" in
        android) shift; run_android "$@" ;;
        desktop) [[ $# -gt 0 ]] && shift; run_desktop "$@" ;;
        -h|--help) sed -n '3,15p' "$0" ;;
        *) run_desktop "$@" ;;
    esac
}

main "$@"
