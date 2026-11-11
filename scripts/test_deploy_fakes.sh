#!/bin/bash

# ============================================================================
# test_deploy_fakes.sh <bin-dir> -- write the fake tools test_deploy.sh puts
# first on PATH. Each fake reads and writes its state under $FAKE at run
# time, so one set of fakes serves every case.
#
#   adb    phone = $FAKE/phone/{present,focus,vname,vcode,lut,install_result}
#   curl   answers with $FAKE/served, or fails to connect when it is absent
#   fvm    `dart run ... --web-root D` serves D/index.html until SIGTERM
# ============================================================================

set -euo pipefail

readonly BIN="$1"

fake() { cat > "${BIN}/$1"; chmod +x "${BIN}/$1"; }

fake adb <<'EOF'
#!/bin/bash
set -euo pipefail
P="$FAKE/phone"
echo "$*" >> "$FAKE/adb.log"
if [[ "${1:-}" == devices ]]; then
    echo "List of devices attached"
    [[ -e "$P/present" ]] && printf '%s\tdevice\n' "$ANDROID_SERIAL"
    exit 0
fi
[[ "$1" == -s ]] && shift 2
[[ -e "$P/present" ]] || { echo "error: device not found" >&2; exit 1; }
case "$*" in
    "shell date +%s") date +%s ;;
    "shell getprop persist.sys.timezone") echo UTC ;;
    install\ -r\ *)
        if [[ "$(cat "$P/install_result" 2>/dev/null)" == incompatible ]]; then
            echo "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures differ]"
            exit 1
        fi
        read -r vname vcode < "$3"
        echo "$vname" > "$P/vname"; echo "$vcode" > "$P/vcode"
        TZ=UTC date '+%F %T' > "$P/lut"
        echo Success ;;
    "shell dumpsys package com.kuhy.kartka")
        [[ -e "$P/vname" ]] || exit 0
        echo "    versionCode=$(cat "$P/vcode") minSdk=24"
        echo "    versionName=$(cat "$P/vname")"
        echo "    lastUpdateTime=$(cat "$P/lut")" ;;
    "shell dumpsys window")
        f="$(cat "$P/focus")"
        echo "  mCurrentFocus=Window{1 u0 ${f}/${f}.Main}" ;;
    shell\ cmd\ package\ resolve-activity*) echo "com.home/.Launcher" ;;
    shell\ monkey\ *) echo com.kuhy.kartka > "$P/focus" ;;
    *) echo "fake adb: unexpected: $*" >&2; exit 1 ;;
esac
EOF

fake curl <<'EOF'
#!/bin/bash
[[ -e "$FAKE/served" ]] || exit 7
cat "$FAKE/served"
EOF

fake fvm <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$*" == "dart pub get" ]] && exit 0
if [[ "$1 $2" == "dart run" ]]; then
    root=""
    while [[ $# -gt 0 ]]; do [[ "$1" == --web-root ]] && root="$2"; shift; done
    cp "$root/index.html" "$FAKE/served"
    trap 'rm -f "$FAKE/served"; exit 0' TERM
    sleep 30 & wait
    exit 0
fi
echo "fake fvm: unexpected: $*" >&2; exit 1
EOF

fake stub_build_web.sh <<'EOF'
#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build/web"
printf '<head>\n<meta name="kartka-build" content="%s">\n' "$KARTKA_BUILD" \
    > "$root/build/web/index.html"
touch "$FAKE/built"
EOF

fake stub_build_android.sh <<'EOF'
#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/app/outputs/flutter-apk"
mkdir -p "$out"
sha="$(git -C "$root" rev-parse --short HEAD)"
printf '0.1.0-%s %s\n' "$sha" "$(git -C "$root" rev-list --count HEAD)" \
    > "$out/app-release.apk"
touch "$FAKE/built"
EOF

fake stub_install_entry.sh <<'EOF'
#!/bin/bash
touch "$XDG_DATA_HOME/kartka.desktop"
EOF
