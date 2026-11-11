#!/bin/bash

# ============================================================================
# deploy_phone.sh -- the phone half of scripts/deploy.sh (sourced, never run).
# Uses SERIAL, APP_ID, APK, SHA, VCODE, WAIT_SECS, WHITELIST_LIB, FOCUS_CONFIG,
# log and die from deploy.sh. Every adb call names the serial, so a second
# device (the emulator) is never the target.
# ============================================================================

phone() { adb -s "${SERIAL}" "$@"; }

phone_present() {
    adb devices | grep -q "^${SERIAL}[[:space:]]*device$" ||
        die "phone ${SERIAL} not connected; nothing installed"
}

# The shared focus-mode helper (phone_deploy). Sourced in a subshell: its own
# die/emit would replace ours.
phone_whitelisted() {
    [[ -f "${WHITELIST_LIB}" ]] || die "whitelist helper missing: ${WHITELIST_LIB}"
    (
        # shellcheck disable=SC2034  # read by check_whitelist
        WHITELIST_FILE="${FOCUS_CONFIG}"
        # shellcheck source=/dev/null
        source "${WHITELIST_LIB}"
        check_whitelist "${APP_ID}"
    ) || die "${APP_ID} not provably in the focus-mode whitelist; nothing installed"
}

# Package of the window in front, e.g. com.kuhy.kartka (empty when none).
phone_focus() {
    phone shell dumpsys window | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^/} ]*\).*/\1/p' |
        tail -1
}

phone_home() {
    phone shell cmd package resolve-activity --brief \
        -c android.intent.category.HOME -a android.intent.action.MAIN | tail -1 | cut -d/ -f1
}

# Rest of the first `dumpsys package` line after "<key>=", CR stripped
# ("5 minSdk=24 ..." for versionCode, "2026-11-10 15:30:17" for lastUpdateTime).
phone_pkg_field() {
    phone shell dumpsys package "${APP_ID}" | tr -d '\r' | sed -n "s/.*[[:space:]]$1=//p" | head -1
}

# lastUpdateTime is phone-local wall time; read it in the phone's zone.
phone_update_epoch() {
    local stamp tz
    stamp="$(phone_pkg_field lastUpdateTime)"
    [[ -n "${stamp}" ]] || die "${APP_ID} is not installed on ${SERIAL}"
    tz="$(phone shell getprop persist.sys.timezone | tr -d '\r')"
    TZ="${tz:-UTC}" date -d "${stamp}" +%s
}

# phone_check <not-before-epoch> <expect-front yes|no>
phone_check() {
    local since="$1" front="$2" have_name have_code updated
    have_name="$(phone_pkg_field versionName)"
    have_code="$(phone_pkg_field versionCode)"
    have_name="${have_name%% *}" have_code="${have_code%% *}"
    updated="$(phone_update_epoch)"
    [[ "${have_name}" == *"-${SHA}" ]] ||
        die "phone runs ${have_name:-nothing}, not build ${SHA}"
    [[ "${have_code}" == "${VCODE}" ]] ||
        die "phone versionCode ${have_code}, want ${VCODE}"
    ((updated >= since)) ||
        die "phone install ($(date -d "@${updated}" '+%F %T')) is older than $(date -d "@${since}" '+%F %T')"
    if [[ "${front}" == yes && "$(phone_focus)" != "${APP_ID}" ]]; then
        die "${APP_ID} is not in front after the launch"
    fi
    log "phone: ${APP_ID} ${have_name} (${have_code})"
}

# Installs with -r only. Launches only when the home screen or kartka itself
# is in front; otherwise kuhy is using the phone and dumpsys alone checks.
phone_install() {
    local start front out launched=no
    start="$(phone shell date +%s | tr -d '\r')"
    front="$(phone_focus)"
    log "adb install -r (data kept)"
    if ! out="$(phone install -r "${APK}" 2>&1)"; then
        printf '%s\n' "${out}" >&2
        die "install failed; the old install is kept (never uninstall)"
    fi
    if [[ "${front}" == "$(phone_home)" || "${front}" == "${APP_ID}" ]]; then
        phone shell monkey -p "${APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null
        launched=yes
        local waited=0
        while [[ "$(phone_focus)" != "${APP_ID}" ]] && ((waited < WAIT_SECS)); do
            sleep 1
            waited=$((waited + 1))
        done
    else
        log "phone in use (${front:-locked}): installed, not launched"
    fi
    phone_check "${start}" "${launched}"
}
