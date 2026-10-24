#!/bin/bash
# ============================================================================
# Registers Kartka's two AniList API clients and stores their ids outside the
# repo. AniList has no API for client registration, so this script does
# everything around the form: it opens the page, puts each field on the
# clipboard in form order, reads the client id back from the clipboard, writes
# ~/.config/kartka/oauth.json (mode 600), and verifies the web client with a
# real login.
#
# AniList's implicit grant always redirects to the client's ONE registered
# URL, so Android (kartka://oauth) and web (127.0.0.1:<wrapperPort>/oauth)
# each need their own client.
#
# Usage: register_anilist.sh [--verify-only] [--no-login]
#   --verify-only  skip registration, only check the stored ids
#   --no-login     skip the interactive web login check
# Requires: jq, xclip, xdg-open, curl (installed if missing).
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
# shellcheck source=oauth_common.sh
source "$HERE/oauth_common.sh"

readonly WRAPPER_PORT="${KARTKA_WRAPPER_PORT:-8791}"
readonly ANDROID_REDIRECT="kartka://oauth"
readonly WEB_REDIRECT="http://127.0.0.1:${WRAPPER_PORT}/oauth"
readonly KEY_ANDROID="KARTKA_ANILIST_CLIENT_ID_ANDROID"
readonly KEY_WEB="KARTKA_ANILIST_CLIENT_ID_WEB"
readonly DEV_PAGE="https://anilist.co/settings/developer"
readonly AUTHORIZE="https://anilist.co/api/v2/oauth/authorize"
readonly GRAPHQL="https://graphql.anilist.co"

VERIFY_ONLY=0
LOGIN_CHECK=1

usage() {
    sed -n '14,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# Reads the client id kuhy copied; re-asks until it is numeric.
read_client_id() {
    local id
    for _ in 1 2 3 4 5; do
        read -r -p "  Copy the new client's ID, then press Enter. " _
        id="$(clip_get | tr -d '[:space:]')"
        if [[ "$id" =~ ^[0-9]+$ ]]; then
            echo "$id"
            return 0
        fi
        echo "  clipboard holds '${id:0:40}', not a numeric client ID." >&2
    done
    die "no numeric client ID after 5 tries"
}

# Registers one client: $1 label, $2 redirect URL, $3 config key.
register_client() {
    local label="$1" redirect="$2" key="$3" id
    echo "== AniList client: Kartka ${label}"
    xdg-open "$DEV_PAGE" >/dev/null 2>&1
    read -r -p "  Click 'Create New Client', then press Enter. " _
    paste_step "Name" "Kartka ${label}"
    paste_step "Redirect URL" "$redirect"
    read -r -p "  Click Save, open the new client, then press Enter. " _
    id="$(read_client_id)"
    config_set "$key" "$id"
    echo "  stored ${key}=${id} in ${KARTKA_OAUTH_FILE}"
}

# Fails unless key $1 holds a numeric id.
check_id() {
    local id
    id="$(config_get "$1")"
    [[ "$id" =~ ^[0-9]+$ ]] || die "${1} missing or not numeric in ${KARTKA_OAUTH_FILE}"
    echo "ok: ${1}=${id}"
}

# Logs in with the web client and proves the token works (Viewer query).
check_web_login() {
    local id url token reply name
    id="$(config_get "$KEY_WEB")"
    echo "== Web login check: approve Kartka Web in the browser."
    echo "   The redirect page may fail to load; that is fine."
    xdg-open "${AUTHORIZE}?client_id=${id}&response_type=token" >/dev/null 2>&1
    read -r -p "  Copy the full address-bar URL, then press Enter. " _
    url="$(clip_get | tr -d '[:space:]')"
    [[ "$url" == "${WEB_REDIRECT}#"* ]] ||
        die "redirect went to '${url%%#*}', want ${WEB_REDIRECT}: fix the client's Redirect URL"
    token="${url#*access_token=}"
    token="${token%%&*}"
    [[ -n "$token" && "$token" != "$url" ]] || die "no access_token in the URL"
    reply="$(curl -sS -m 20 -X POST "$GRAPHQL" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -H "Authorization: Bearer ${token}" \
        --data '{"query":"query { Viewer { id name } }"}')"
    name="$(jq -r '.data.Viewer.name // empty' <<<"$reply")"
    [[ -n "$name" ]] ||
        die "token rejected: $(jq -r '.errors[0].message // "no Viewer"' <<<"$reply")"
    echo "ok: web client logged in as ${name} (token discarded)"
}

verify() {
    config_check_mode
    check_id "$KEY_ANDROID"
    check_id "$KEY_WEB"
    if [[ "$LOGIN_CHECK" -eq 1 ]]; then check_web_login; fi
    echo "Android client: verified on the phone at first AniList login."
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verify-only) VERIFY_ONLY=1 ;;
            --no-login) LOGIN_CHECK=0 ;;
            -h | --help) usage ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done
    ensure_tools jq xclip xdg-open curl
    if [[ "$VERIFY_ONLY" -eq 0 ]]; then
        register_client "Android" "$ANDROID_REDIRECT" "$KEY_ANDROID"
        register_client "Web" "$WEB_REDIRECT" "$KEY_WEB"
    fi
    verify
    echo "Done. Builds read ${KARTKA_OAUTH_FILE} via --dart-define-from-file."
}

main "$@"
