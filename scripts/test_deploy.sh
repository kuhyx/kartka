#!/bin/bash

# ============================================================================
# test_deploy.sh -- failure paths and happy paths of scripts/deploy.sh.
#
# Everything is fake and lives in one temp dir: a git repo with a bare origin
# stands in for ~/src/kartka (its build scripts are stubs), and fake adb /
# curl / fvm come first on PATH. adb keeps the "phone" as files; the fake APK
# holds "<versionName> <versionCode>" so the fake install can record them.
# No test reaches the real phone, port 47391 or ~/.local/share.
#
#   scripts/test_deploy.sh        exit 0 when every case passes
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY="${HERE}/deploy.sh"
readonly REAL_WHITELIST_LIB="${HOME}/.claude/scripts/lib/phone_deploy_device.sh"
TMP="$(mktemp -d)"
readonly TMP
trap 'pkill -f "${TMP}/" 2>/dev/null || true; rm -rf "${TMP}"' EXIT
FAILS=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Fake tools and stub repo scripts (test_deploy_fakes.sh); state in $FAKE.
write_fakes() { mkdir -p "$1" && "${HERE}/test_deploy_fakes.sh" "$1"; }

# A fresh world: origin + clone + phone state + config files.
setup() {
    local w="${TMP}/w$1"
    export FAKE="${w}/fake"
    mkdir -p "$FAKE/phone" "${w}/xdg"
    write_fakes "${w}/bin"
    git init -q --bare "${w}/origin.git"
    git clone -q "${w}/origin.git" "${w}/src" 2>/dev/null
    mkdir -p "${w}/src/scripts" "${w}/src/desktop"
    cp "${w}/bin/stub_build_web.sh" "${w}/src/scripts/build_web.sh"
    cp "${w}/bin/stub_build_android.sh" "${w}/src/scripts/build_android.sh"
    cp "${w}/bin/stub_install_entry.sh" "${w}/src/desktop/install_desktop_entry.sh"
    printf 'name: kartka\nversion: 0.1.0+1\n' > "${w}/src/pubspec.yaml"
    printf 'build/\n' > "${w}/src/.gitignore"
    git -C "${w}/src" add -A
    git -C "${w}/src" -c user.name=t -c user.email=t@t commit -qm init
    git -C "${w}/src" push -q origin HEAD 2>/dev/null
    printf '{}' > "${w}/oauth.json"
    printf 'key' > "${w}/debug.keystore"
    printf 'WHITELIST="\ncom.kuhy.kartka\n"\n' > "${w}/focus.sh"
    printf 'device' > "$FAKE/phone/present"
    printf 'com.home' > "$FAKE/phone/focus"
    export PATH="${w}/bin:${ORIG_PATH}"
    export KARTKA_SRC="${w}/src" KARTKA_OAUTH="${w}/oauth.json"
    export KARTKA_KEYSTORE="${w}/debug.keystore" FOCUS_MODE_CONFIG="${w}/focus.sh"
    export KARTKA_WHITELIST_LIB="${REAL_WHITELIST_LIB}" KARTKA_CAPPED=""
    export KARTKA_WAIT_SECS=5 XDG_DATA_HOME="${w}/xdg" ANDROID_SERIAL=FAKE01
    W="$w"
}

run_deploy() { "${DEPLOY}" "$@" > "${W}/out" 2>&1; }

expect() {  # expect <name> <want-exit 0|nonzero> [deploy args]
    local name="$1" want="$2" rc=0
    shift 2
    run_deploy "$@" || rc=$?
    if [[ "$want" == 0 && "$rc" == 0 ]] || [[ "$want" != 0 && "$rc" != 0 ]]; then
        pass "$name (exit ${rc})"
        return 0
    fi
    fail "$name (exit ${rc}, want ${want})"
    sed 's/^/     | /' "${W}/out" | tail -15
    return 1
}

check() {  # check <name> <command...>
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

no_wipe() { ! grep -Eq 'uninstall|pm clear' "$FAKE/adb.log" 2>/dev/null; }
not_installed() { ! grep -q 'install -r' "$FAKE/adb.log" 2>/dev/null; }
not_built() { [[ ! -e "$FAKE/built" ]]; }
port_free() { [[ ! -e "$FAKE/served" ]]; }
out_has() { grep -q -- "$1" "${W}/out"; }

[[ -x "${DEPLOY}" ]] || { echo "FAIL scripts/deploy.sh missing"; exit 1; }
readonly ORIG_PATH="$PATH"

setup 1
if expect "C1 full deploy, phone on home" 0; then
    check "C1 launched" grep -q monkey "$FAKE/adb.log"
    check "C1 installed with -r" grep -q 'install -r' "$FAKE/adb.log"
    check "C6 desktop entry installed" test -e "${W}/xdg/kartka.desktop"
    check "C9 own wrapper stopped" port_free
    check "C2 no uninstall/pm clear" no_wipe
fi
expect "C10 second run" 0 || :
rm -f "$FAKE/built"
expect "C5 verify-only right after" 0 --verify-only && check "C5 built nothing" not_built
git -C "${W}/src" -c user.name=t -c user.email=t@t commit -qm next --allow-empty
git -C "${W}/src" push -q origin HEAD 2>/dev/null
git -C "${W}/src" reset -q --hard HEAD~1
expect "C5 verify-only after newer push" 1 --verify-only || :

setup 2
printf 'org.signal' > "$FAKE/phone/focus"
expect "C3 phone in use" 0 && check "C3 not launched" bash -c "! grep -q monkey '$FAKE/adb.log'"
check "C3 other app still in front" grep -qx org.signal "$FAKE/phone/focus"

setup 3
rm "$FAKE/phone/present"
expect "C4 phone absent" 1 && check "C4 nothing installed" not_installed

setup 4
rm "${W}/oauth.json"
expect "C8 oauth missing" 1 && check "C8 names file" out_has oauth.json && check "C8 not built" not_built

setup 5
printf 'x\n' >> "${W}/src/pubspec.yaml"
expect "C8 dirty tracked tree" 1 && check "C8 dirty not built" not_built

setup 6
git -C "${W}/src" -c user.name=t -c user.email=t@t commit -qm local --allow-empty
git clone -q "${W}/origin.git" "${W}/other" 2>/dev/null
git -C "${W}/other" -c user.name=t -c user.email=t@t commit -qm remote --allow-empty
git -C "${W}/other" push -q origin HEAD 2>/dev/null
expect "C8 not fast-forward" 1 && check "C8 non-ff not built" not_built

setup 7
printf 'incompatible' > "$FAKE/phone/install_result"
expect "update incompatible" 1 && check "incompatible: no wipe" no_wipe

setup 8
printf 'WHITELIST="\norg.other\n"\n' > "${W}/focus.sh"
expect "not whitelisted" 1 && check "whitelist: nothing installed" not_installed

setup 9
expect "C7 setup deploy" 0 || :
sha="$(git -C "${W}/src" rev-parse --short HEAD)"
printf '<meta name="kartka-build" content="%s">' "$sha" > "$FAKE/served"
touch "$FAKE/foreign"
expect "C7 port taken, new sha" 0 && check "C7 says restart needed" out_has "restart needed"
check "C7 foreign wrapper not killed" test -e "$FAKE/served"
printf '<meta name="kartka-build" content="0000000">' > "$FAKE/served"
expect "C7 port taken, old sha" 1 || :

if ((FAILS > 0)); then echo "${FAILS} failed"; exit 1; fi
echo "all passed"
