#!/bin/bash

# ============================================================================
# signing.sh -- release signing with key rotation (sourced, never run).
#
# Release APKs carry the shared release key (android/key.properties, the key
# phone_deploy expects) PLUS an APK Signature Scheme v3 proof-of-rotation
# lineage from this machine's debug key. The Pixel's kartka was installed
# debug-signed; the lineage lets `adb install -r` move it to the release key
# with its library intact (no uninstall). Passwords reach keytool/apksigner
# through env vars, never argv (argv is world-readable in /proc).
#
# Needs ROOT (repo root). Sets KARTKA_SIGN_* via load_key_props.
# ============================================================================

readonly DEBUG_KEYSTORE="${KARTKA_DEBUG_KEYSTORE:-${HOME}/.android/debug.keystore}"
# AGP's fixed debug-key credentials (public by design).
readonly DEBUG_ALIAS="androiddebugkey"
export KARTKA_DEBUG_PASS="android"

key_props_file() { printf '%s\n' "${ROOT}/android/key.properties"; }

# key.properties -> KARTKA_SIGN_{STORE,ALIAS} + exported password vars.
# storeFile is relative to android/app (Gradle's file()), or absolute.
load_key_props() {
    local props value
    props="$(key_props_file)"
    [[ -f "${props}" ]] || { echo "error: release key missing: ${props}" >&2; return 1; }
    prop() { sed -n "s/^$1=//p" "${props}" | head -1; }
    value="$(prop storeFile)"
    [[ "${value}" == /* ]] || value="${ROOT}/android/app/${value}"
    KARTKA_SIGN_STORE="${value}"
    KARTKA_SIGN_ALIAS="$(prop keyAlias)"
    KARTKA_SIGN_STOREPASS="$(prop storePassword)"
    KARTKA_SIGN_KEYPASS="$(prop keyPassword)"
    export KARTKA_SIGN_STOREPASS KARTKA_SIGN_KEYPASS
    [[ -f "${KARTKA_SIGN_STORE}" ]] ||
        { echo "error: key.properties names a missing keystore: ${KARTKA_SIGN_STORE}" >&2; return 1; }
    [[ -f "${DEBUG_KEYSTORE}" ]] ||
        { echo "error: debug key missing (rotation source): ${DEBUG_KEYSTORE}" >&2; return 1; }
}

# Newest apksigner: PATH, then the SDK named in android/local.properties.
find_apksigner() {
    local sdk
    APKSIGNER="$(command -v apksigner || true)"
    if [[ -z "${APKSIGNER}" ]]; then
        sdk="$(sed -n 's/^sdk.dir=//p' "${ROOT}/android/local.properties" 2>/dev/null)"
        APKSIGNER="$(find "${sdk:-${ANDROID_HOME:-/nonexistent}}/build-tools" -maxdepth 2 \
            -name apksigner 2>/dev/null | sort -V | tail -1 || true)"
    fi
    [[ -n "${APKSIGNER}" ]] || { echo "error: no apksigner found" >&2; return 1; }
}

# cert_sha256 <keystore> <alias> <storepass-env-var>: lowercase hex digest.
cert_sha256() {
    keytool -list -v -keystore "$1" -alias "$2" -storepass:env "$3" 2>/dev/null |
        sed -n 's/^[[:space:]]*SHA256: //p' | head -1 | tr -d ':' | tr 'A-F' 'a-f'
}

# sign_rotated <apk>: re-sign in place, debug key -> release key lineage.
sign_rotated() {
    local apk="$1" lineage="${ROOT}/build/kartka-signing-lineage.bin"
    load_key_props && find_apksigner || return 1
    if [[ ! -f "${lineage}" ]]; then
        mkdir -p "$(dirname "${lineage}")"
        "${APKSIGNER}" rotate --out "${lineage}" \
            --old-signer --ks "${DEBUG_KEYSTORE}" --ks-key-alias "${DEBUG_ALIAS}" \
            --ks-pass env:KARTKA_DEBUG_PASS --key-pass env:KARTKA_DEBUG_PASS \
            --new-signer --ks "${KARTKA_SIGN_STORE}" --ks-key-alias "${KARTKA_SIGN_ALIAS}" \
            --ks-pass env:KARTKA_SIGN_STOREPASS --key-pass env:KARTKA_SIGN_KEYPASS
    fi
    "${APKSIGNER}" sign --rotation-min-sdk-version 28 \
        --ks "${DEBUG_KEYSTORE}" --ks-key-alias "${DEBUG_ALIAS}" \
        --ks-pass env:KARTKA_DEBUG_PASS --key-pass env:KARTKA_DEBUG_PASS \
        --next-signer --ks "${KARTKA_SIGN_STORE}" --ks-key-alias "${KARTKA_SIGN_ALIAS}" \
        --ks-pass env:KARTKA_SIGN_STOREPASS --key-pass env:KARTKA_SIGN_KEYPASS \
        --lineage "${lineage}" "${apk}"
}

# check_apk_signer <apk>: 0 when the APK's signer is the release key and its
# lineage starts at the debug key; otherwise prints why and returns 1.
check_apk_signer() {
    local apk="$1" release debug signer lineage
    load_key_props && find_apksigner || return 1
    release="$(cert_sha256 "${KARTKA_SIGN_STORE}" "${KARTKA_SIGN_ALIAS}" KARTKA_SIGN_STOREPASS)"
    debug="$(cert_sha256 "${DEBUG_KEYSTORE}" "${DEBUG_ALIAS}" KARTKA_DEBUG_PASS)"
    signer="$("${APKSIGNER}" verify --print-certs "${apk}" 2>/dev/null |
        grep -m1 -i 'SHA-256 digest' | grep -oE '[0-9a-f]{64}' || true)"
    lineage="$("${APKSIGNER}" lineage --in "${apk}" --print-certs 2>/dev/null |
        grep -i 'SHA-256 digest' | grep -oE '[0-9a-f]{64}' | paste -sd, || true)"
    if [[ -z "${release}" || "${signer}" != "${release}" ]]; then
        echo "signer ${signer:-unreadable} is not the release key ${release:-unreadable}" >&2
        return 1
    fi
    if [[ "${lineage}" != "${debug},${release}" ]]; then
        echo "lineage '${lineage:-none}' does not rotate ${debug} -> ${release}" >&2
        return 1
    fi
    echo "signer ok: release ${release:0:8}, rotated from debug ${debug:0:8}"
}
