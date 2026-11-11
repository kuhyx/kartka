#!/bin/bash
# shellcheck source-path=SCRIPTDIR

# ============================================================================
# deploy.sh -- install the current main of kartka on the Pixel and the desktop.
#
#   scripts/deploy.sh                 pull ~/src/kartka (ff-only), build the web
#                                     bundle and the release APK there, install
#                                     both, then run the health checks
#   scripts/deploy.sh --verify-only   fetch origin, build nothing, run the
#                                     health checks against origin/main
#
# Health (any failure exits non-zero):
#   phone    dumpsys: versionName ends in -<sha>, versionCode = commit count,
#            lastUpdateTime after the run start (--verify-only: after the
#            commit time); kartka in front when this run launched it
#   desktop  GET / on 127.0.0.1:47391 serves <meta name="kartka-build"> = sha.
#            A wrapper already there is never killed: new sha = "restart
#            needed", exit 0; old sha = exit 1. One we start, we stop.
#
# Never uninstalls or `pm clear`s (that wipes the library), never launches over
# another app, never touches the emulator or the agent ports 47392/9342.
# Builds run through capped.sh (4G, 20 % CPU). Overrides for the test
# (scripts/test_deploy.sh): KARTKA_SRC, ANDROID_SERIAL, KARTKA_OAUTH,
# KARTKA_KEYSTORE, KARTKA_WHITELIST_LIB, FOCUS_MODE_CONFIG, KARTKA_CAPPED,
# KARTKA_WAIT_SECS.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SRC="${KARTKA_SRC:-${HOME}/src/kartka}"
readonly SERIAL="${ANDROID_SERIAL:-23181JEGR08034}"
readonly APP_ID="com.kuhy.kartka"
readonly PORT=47391
readonly OAUTH="${KARTKA_OAUTH:-${HOME}/.config/kartka/oauth.json}"
readonly KEYSTORE="${KARTKA_KEYSTORE:-${HOME}/.android/debug.keystore}"
readonly WHITELIST_LIB="${KARTKA_WHITELIST_LIB:-${HOME}/.claude/scripts/lib/phone_deploy_device.sh}"
readonly FOCUS_CONFIG="${FOCUS_MODE_CONFIG:-${HOME}/src/phone-focus-mode/config.sh}"
readonly CAPPED="${KARTKA_CAPPED-${HOME}/.claude/scripts/capped.sh}"
readonly WAIT_SECS="${KARTKA_WAIT_SECS:-120}"
readonly APK="${SRC}/build/app/outputs/flutter-apk/app-release.apk"
readonly ANDROID_STEPS=(kernel aot java r8 apk)

log() { printf '==> %s\n' "$1"; }
die() { printf 'deploy: %s\n' "$1" >&2; exit 1; }

# shellcheck source=lib/deploy_phone.sh
source "${SCRIPT_DIR}/lib/deploy_phone.sh"
# shellcheck source=lib/deploy_desktop.sh
source "${SCRIPT_DIR}/lib/deploy_desktop.sh"

# Runs "$@" in the capped scope, or plainly when KARTKA_CAPPED is empty.
capped() {
    if [[ -n "${CAPPED}" ]]; then
        CAP_MEM=4G CAP_CPU_PCT=20 "${CAPPED}" "$@"
    else
        "$@"
    fi
}

# Untracked files (kuhy's .claude/) are fine; tracked edits are not.
preflight() {
    [[ -f "${OAUTH}" ]] || die "OAuth defines missing: ${OAUTH}"
    [[ -f "${KEYSTORE}" ]] || die "signing key missing: ${KEYSTORE}"
    # The shared release key (gitignored; build_android.sh signs with it plus
    # the debug -> release rotation lineage, scripts/lib/signing.sh).
    [[ -f "${SRC}/android/key.properties" ]] ||
        die "release key missing: ${SRC}/android/key.properties"
    if ! git -C "${SRC}" diff --quiet || ! git -C "${SRC}" diff --cached --quiet; then
        die "${SRC} has uncommitted tracked changes"
    fi
    log "git pull --ff-only in ${SRC}"
    git -C "${SRC}" pull --ff-only --quiet || die "${SRC} cannot fast-forward"
    phone_present
    phone_whitelisted
}

# Sets SHA (short), VCODE (commit count), CTIME (commit epoch) for a ref.
target() {
    SHA="$(git -C "${SRC}" rev-parse --short "$1")"
    VCODE="$(git -C "${SRC}" rev-list --count "$1")"
    CTIME="$(git -C "${SRC}" log -1 --format=%ct "$1")"
}

build() {
    log "building the web bundle (${SHA})"
    capped env KARTKA_BUILD="${SHA}" "${SRC}/scripts/build_web.sh"
    local step
    for step in "${ANDROID_STEPS[@]}"; do
        log "building the APK: ${step}"
        capped "${SRC}/scripts/build_android.sh" release "${step}"
    done
    [[ -f "${APK}" ]] || die "no APK at ${APK}"
}

deploy() {
    preflight
    target HEAD
    build
    phone_install
    log "installing the desktop launcher"
    "${SRC}/desktop/install_desktop_entry.sh" >/dev/null
    desktop_check
    log "deployed ${SHA}"
}

verify_only() {
    git -C "${SRC}" fetch --quiet origin || die "git fetch failed in ${SRC}"
    target origin/main
    phone_present
    phone_check "${CTIME}" no
    desktop_check
    log "verified ${SHA}"
}

main() {
    case "${1:-}" in
        "") deploy ;;
        --verify-only) verify_only ;;
        -h|--help) sed -n '5,28p' "$0" ;;
        *) die "unknown argument: $1" ;;
    esac
}

main "$@"
