#!/bin/bash
# ============================================================================
# Walks the two Google Cloud console steps that "Sign in with Google" for the
# sync account needs, and runs everything around them. Run it in a real
# terminal (it reads Enter presses), not through Claude's `!`.
#
#   1. Android: an Android OAuth client for com.kuhy.kartka + the SHA-1 of the
#      key that signs the release APK. Without it the picker reports
#      "cancelled" (DEVELOPER_ERROR / UNREGISTERED_ON_API_CONSOLE).
#   2. Web (desktop): http://127.0.0.1:47391 as an authorised JavaScript
#      origin on the existing Web client, so the GIS button works there.
#      Additive only: never remove localhost:8765 (seed_session uses it).
#
# Neither has an API (no create/patch for OAuth clients). The SHA-1 comes from
# the keystore android/app/build.gradle.kts actually signs release with
# (today the debug key; moving keys would break `adb install -r`). The new
# Android client id goes to ~/.config/kartka/oauth.json (0600), never the repo.
#
# Usage:
#   tools/sync/register_google_signin.sh                # both steps + verify
#   tools/sync/register_google_signin.sh --sha1         # print the SHA-1
#   tools/sync/register_google_signin.sh --verify-only
# Requires: keytool, jq, xclip, xdg-open, curl, adb (verification).
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
REPO_DIR="$(cd "$HERE/../.." && pwd)"
readonly REPO_DIR
# shellcheck source=tools/tracking/oauth_common.sh
source "$HERE/../tracking/oauth_common.sh"

readonly PROJECT="kuhy-syncs"
readonly PACKAGE="com.kuhy.kartka"
readonly WEB_CLIENT_ID="845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com"
readonly ORIGIN="http://127.0.0.1:${WRAPPER_PORT}"
readonly CLIENTS_URL="https://console.cloud.google.com/auth/clients?project=${PROJECT}"
readonly WEB_CLIENT_URL="https://console.cloud.google.com/auth/clients/${WEB_CLIENT_ID}?project=${PROJECT}"
readonly GRADLE="${KARTKA_GRADLE:-$REPO_DIR/android/app/build.gradle.kts}"
readonly DEVICE="${ANDROID_SERIAL:-23181JEGR08034}"
readonly ID_KEY="KARTKA_GOOGLE_CLIENT_ID_ANDROID"
readonly TRIES="${KARTKA_VERIFY_TRIES:-6}"
readonly PAUSE="${KARTKA_VERIFY_PAUSE:-10}"

# Prints the SHA-1 of the key the release build is signed with.
release_sha1() {
    [[ -f "$GRADLE" ]] || die "missing $GRADLE"
    grep -q 'signingConfig = signingConfigs.getByName("debug")' "$GRADLE" ||
        die "release is no longer signed with the debug key; teach this script the new keystore"
    local store="$HOME/.android/debug.keystore" sha
    [[ -f "$store" ]] || die "missing $store"
    sha="$(keytool -list -v -keystore "$store" -alias androiddebugkey \
        -storepass android 2>/dev/null | grep -m1 -E '^[[:space:]]*SHA1:' |
        sed 's/.*SHA1: //' | tr -d ' \r')"
    [[ "$sha" =~ ^([0-9A-F]{2}:){19}[0-9A-F]{2}$ ]] || die "no SHA-1 in $store"
    printf '%s\n' "$sha"
}

# True when Google accepts $ORIGIN for the Web client (no secrets involved).
origin_allowed() {
    curl -s -m 15 -H 'X-Requested-With: XmlHttpRequest' \
        "https://accounts.google.com/o/oauth2/iframerpc?action=checkOrigin&origin=${ORIGIN//:/%3A}&client_id=${WEB_CLIENT_ID}" |
        grep -q '"valid":true'
}

# Cross-checks $1 against the signer of the built release APK, when both the
# APK and apksigner exist: the fingerprint must be the one Android reports.
check_apk_signer() {
    local apk="${KARTKA_APK:-$REPO_DIR/build/app/outputs/flutter-apk/app-release.apk}"
    local sdk signer got
    [[ -f "$apk" ]] || return 0
    sdk="$(grep -h '^sdk.dir=' "$REPO_DIR/android/local.properties" 2>/dev/null | cut -d= -f2)"
    signer="$(find "${sdk:-/nonexistent}/build-tools" -maxdepth 2 -name apksigner 2>/dev/null | sort | tail -1)"
    [[ -n "$signer" ]] || return 0
    got="$("$signer" verify --print-certs "$apk" 2>/dev/null |
        sed -n 's/.*certificate SHA-1 digest: //p' | head -1)"
    [[ -n "$got" ]] || { echo "  (apksigner gave no answer; APK not cross-checked)"; return 0; }
    local want="${1//:/}"
    [[ "${got^^}" == "$want" ]] ||
        die "built APK is signed by SHA-1 '$got', not $1; rebuild or fix the script"
    echo "  the built APK is signed with this key"
}

register_android() {
    local sha id
    sha="$(release_sha1)"
    check_apk_signer "$sha"
    echo "==> Android client (one form, three fields)"
    xdg-open "$CLIENTS_URL" >/dev/null 2>&1 || echo "  open: $CLIENTS_URL"
    echo "  Click '+ Create client', Application type = Android."
    paste_step "Name" "kartka"
    paste_step "Package name" "$PACKAGE"
    paste_step "SHA-1 certificate fingerprint" "$sha"
    read -r -p "  Click Create, copy the new client id (Ctrl-C), press Enter. " _
    id="$(clip_get)"
    if [[ "$id" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
        config_set "$ID_KEY" "$id"
        echo "  stored $ID_KEY in $KARTKA_OAUTH_FILE"
    else
        echo "  clipboard does not look like a client id; not stored (the app does not need it)"
    fi
}

register_web() {
    echo "==> Web client: authorised JavaScript origin"
    if origin_allowed; then
        echo "  $ORIGIN is already allowed; nothing to do"
        return 0
    fi
    xdg-open "$WEB_CLIENT_URL" >/dev/null 2>&1 || echo "  open: $WEB_CLIENT_URL"
    echo "  Under 'Authorised JavaScript origins' click '+ Add URI'."
    paste_step "origin" "$ORIGIN"
    read -r -p "  Click Save (change nothing else), then press Enter. " _
}

verify_web() {
    local i
    for ((i = 1; i <= TRIES; i++)); do
        if origin_allowed; then
            echo "OK   web: Google accepts $ORIGIN"
            return 0
        fi
        if [[ "$i" -lt "$TRIES" ]]; then sleep "$PAUSE"; fi
    done
    echo "FAIL web: $ORIGIN not accepted yet (propagation can take minutes); rerun --verify-only"
    return 1
}

verify_android() {
    adb devices | grep -q "^${DEVICE}[[:space:]]*device" || {
        echo "FAIL android: phone $DEVICE not attached; rerun --verify-only"
        return 1
    }
    echo "  On the phone: More > Sync > Sign in > 'Sign in with Google', pick the sync account."
    read -r -p "  Press Enter once the sync screen is showing again. " _
    local dump
    dump="$(mktemp --suffix=.xml)"
    adb -s "$DEVICE" shell uiautomator dump /sdcard/kartka_ui.xml >/dev/null 2>&1
    adb -s "$DEVICE" pull /sdcard/kartka_ui.xml "$dump" >/dev/null 2>&1
    if grep -q 'Disconnect' "$dump" && ! grep -q 'was cancelled' "$dump"; then
        rm -f "$dump"
        echo "OK   android: signed in"
        return 0
    fi
    echo "FAIL android: not signed in (screen dump: $dump); rerun --verify-only"
    return 1
}

verify_all() {
    local rc=0
    verify_web || rc=1
    verify_android || rc=1
    return "$rc"
}

main() {
    case "${1:-}" in
        --sha1) release_sha1 ;;
        --verify-only) ensure_tools curl adb && verify_all ;;
        "")
            ensure_tools keytool jq xclip xdg-open curl adb
            register_android
            register_web
            verify_all
            ;;
        *) die "usage: $0 [--sha1|--verify-only]" ;;
    esac
}

main "$@"
