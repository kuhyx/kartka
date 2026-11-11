#!/bin/bash

# ============================================================================
# build_android.sh -- build the arm64 APK in steps that each fit a 60 s cap.
#
#   scripts/build_android.sh [release|profile] [step]
#
# Steps, in cold-build order (each one resumable, each < 60 s under
# `CAP_MEM=4G CAP_CPU_PCT=20 ~/.claude/scripts/capped.sh`):
#   kernel   Dart front end (`flutter assemble kernel_snapshot_program`)
#   aot      gen_snapshot + Flutter assets (Gradle compileFlutterBuild<Mode>)
#   java     plugin + app JVM sources (Gradle; the app's R class needs the
#            Flutter assets, hence after aot)
#   r8       shrink + dex (Gradle minify<Mode>WithR8; release only)
#   apk      package + sign (Gradle :app:assemble<Mode>); the default step.
#            It runs whatever earlier step is out of date, so on a warm tree
#            (or uncapped, as ./run.sh android does) it is the whole build.
#   gradle <args>   any Gradle task with the same props (e.g. `-m <task>`)
#
# Output: build/app/outputs/flutter-apk/app-<mode>.apk. Only arm64 is built
# (the phone is arm64); the Gradle props and Dart defines mirror what
# `flutter build apk --target-platform android-arm64` passes (flutter_tools
# lib/src/android/gradle.dart, gradle/src/main/kotlin/tasks/
# BaseFlutterTaskHelper.kt), so `kernel` shares flutter assemble's cache with
# the Gradle task. OAuth client ids come from ~/.config/kartka/oauth.json
# when it exists, exactly as run.sh passes them (--dart-define-from-file).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="${SCRIPT_DIR%/scripts}"
readonly OAUTH_DEFINES="${HOME}/.config/kartka/oauth.json"
readonly TARGET_PLATFORM="android-arm64"
# ~/.gradle/gradle.properties asks for a 5 GiB heap and beats the project
# file; a -D on the command line beats both. R8 runs in this JVM, so the heap
# bounds it; 1.5 GiB leaves room under the 4 GiB scope for frontend_server /
# gen_snapshot.
readonly GRADLE_JVMARGS="-Xmx1536m -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=192m"
# The JDK flutter_tools hands Gradle (`flutter config --jdk-dir`); the system
# default (27) fails AGP's jlink transform.
readonly FLUTTER_SETTINGS="${HOME}/.config/flutter/settings"

log() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

usage() { sed -n '3,26p' "$0"; exit "${1:-0}"; }

# pub get + gradlew + local.properties, only when missing or stale.
# local.properties carries versionName/versionCode from pubspec.yaml.
ensure_config() {
    local props="${ROOT}/android/local.properties"
    if [[ -x "${ROOT}/android/gradlew" && -f "${ROOT}/.dart_tool/package_config.json" &&
        "$props" -nt "${ROOT}/pubspec.yaml" && "$props" -nt "${ROOT}/pubspec.lock" ]]; then
        return
    fi
    log "flutter build apk --config-only (pub get, gradlew, local.properties)"
    (cd "${ROOT}" && fvm flutter build apk --config-only >/dev/null)
}

b64() { printf '%s' "$1" | base64 -w0; }

# The -Pdart-defines value flutter_tools would compute: the OAuth file's
# entries, then FLUTTER_BUILD_NAME/NUMBER and the SDK identity, each
# base64("KEY=VALUE"), comma-joined.
dart_defines() {
    local -a defs=()
    local key value version
    if [[ -f "${OAUTH_DEFINES}" ]]; then
        while IFS=$'\t' read -r key value; do
            defs+=("$(b64 "${key}=${value}")")
        done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "${OAUTH_DEFINES}")
    fi
    version="$(sed -n 's/^version: *//p' "${ROOT}/pubspec.yaml")"
    local -A sdk=()
    while IFS=$'\t' read -r key value; do sdk[$key]="$value"; done < <(
        cd "${ROOT}" && fvm flutter --version --machine 2>/dev/null |
            jq -r 'to_entries[] | "\(.key)\t\(.value)"')
    defs+=("$(b64 "KARTKA_BUILD=${KARTKA_BUILD}")")
    defs+=("$(b64 "FLUTTER_BUILD_NAME=${version%%+*}")")
    defs+=("$(b64 "FLUTTER_BUILD_NUMBER=${version##*+}")")
    defs+=("$(b64 "FLUTTER_VERSION=${sdk[frameworkVersion]}")")
    defs+=("$(b64 "FLUTTER_CHANNEL=${sdk[channel]}")")
    defs+=("$(b64 "FLUTTER_GIT_URL=${sdk[repositoryUrl]}")")
    defs+=("$(b64 "FLUTTER_FRAMEWORK_REVISION=${sdk[frameworkRevision]:0:10}")")
    defs+=("$(b64 "FLUTTER_ENGINE_REVISION=${sdk[engineRevision]:0:10}")")
    defs+=("$(b64 "FLUTTER_DART_VERSION=${sdk[dartSdkVersion]}")")
    local IFS=,
    printf '%s\n' "${defs[*]}"
}

# Value of a key in android/local.properties (sdk.dir, flutter.sdk).
local_prop() { sed -n "s/^$1=//p" "${ROOT}/android/local.properties"; }

gradle() {
    local sdk ndks
    sdk="$(local_prop sdk.dir)"
    ndks="$(find "${sdk}/ndk" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | paste -sd,)"
    local jdk="${JAVA_HOME:-}"
    if [[ -f "${FLUTTER_SETTINGS}" ]]; then
        jdk="$(jq -r --arg d "$jdk" '.["jdk-dir"] // $d' "${FLUTTER_SETTINGS}")"
    fi
    if [[ -n "$jdk" ]]; then export JAVA_HOME="$jdk" PATH="${jdk}/bin:${PATH}"; fi
    (cd "${ROOT}/android" && ./gradlew --no-daemon \
        "-Dorg.gradle.jvmargs=${GRADLE_JVMARGS}" \
        "-Ptarget-platform=${TARGET_PLATFORM}" -Ptarget=lib/main.dart \
        -Pbase-application-name=android.app.Application \
        "-Pdart-defines=${DEFINES}" -Pdart-obfuscation=false \
        -Ptrack-widget-creation=true -Ptree-shake-icons=true \
        "-PkartkaBuild=${KARTKA_BUILD}" "-PkartkaVersionCode=${KARTKA_VERSION_CODE}" \
        "-Pflutter.androidSdkRoot=${sdk}" "-Pflutter.installedNdkVersions=${ndks}" \
        "$@")
}

# The Dart front end alone, with the exact -d set the Gradle task passes so
# both share one flutter assemble build prefix (then `aot` skips the kernel).
# Own depfile: the Gradle task's flutter_build.d drives its up-to-date check.
kernel() {
    local min_sdk
    min_sdk="$(sed -n 's/.*val minSdkVersion: Int = \([0-9]*\).*/\1/p' \
        "$(local_prop flutter.sdk)/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt")"
    [[ -n "$min_sdk" ]] || die "cannot read flutter.minSdkVersion from the SDK"
    local out="${ROOT}/build/app/intermediates/flutter/${MODE}"
    (cd "${ROOT}" && fvm flutter --quiet assemble --no-version-check \
        --depfile "${out}/kernel_step.d" --output "${out}" \
        -dTargetFile=lib/main.dart -dTargetPlatform=android \
        "-dBuildMode=${MODE}" -dTrackWidgetCreation=true -dTreeShakeIcons=true \
        "--DartDefines=${DEFINES}" -dFlavor= \
        "-dAndroidArchs=${TARGET_PLATFORM}" "-dMinSdkVersion=${min_sdk}" \
        kernel_snapshot_program)
}

run_step() {
    local name="$1" t0=$SECONDS
    case "$1" in
        kernel) kernel ;;
        aot) gradle ":app:compileFlutterBuild${CAP_MODE}" ;;
        java) gradle ":app:compile${CAP_MODE}JavaWithJavac" ;;
        r8)
            # Flutter enables minify on the release build type only.
            if [[ "$MODE" == release ]]; then gradle ":app:minify${CAP_MODE}WithR8"; fi
            ;;
        apk) gradle ":app:assemble${CAP_MODE}" ;;
        gradle) shift; gradle "$@" ;;
        *) usage 2 >&2 ;;
    esac
    log "${name} done in $((SECONDS - t0)) s"
}

main() {
    [[ "${1:-}" == -h || "${1:-}" == --help ]] && usage
    MODE="${1:-release}"
    local step="${2:-apk}"
    case "$MODE" in
        release) CAP_MODE=Release ;;
        profile) CAP_MODE=Profile ;;
        *) usage 2 >&2 ;;
    esac
    readonly MODE CAP_MODE
    if ! command -v jq >/dev/null 2>&1; then
        log "installing jq"
        sudo pacman -S --needed --noconfirm jq
    fi
    ensure_config
    # Every APK names its commit: versionName <pubspec>-<sha>, versionCode =
    # commit count (monotonic on main, so `adb install -r` never downgrades).
    KARTKA_BUILD="$(git -C "${ROOT}" rev-parse --short HEAD)"
    KARTKA_VERSION_CODE="$(git -C "${ROOT}" rev-list --count HEAD)"
    readonly KARTKA_BUILD KARTKA_VERSION_CODE
    DEFINES="$(dart_defines)"
    readonly DEFINES
    run_step "$step" "${@:3}"
    if [[ "$step" == apk ]]; then
        ls -l "${ROOT}/build/app/outputs/flutter-apk/app-${MODE}.apk"
    fi
}

main "$@"
