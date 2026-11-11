#!/bin/bash

# ============================================================================
# build_web.sh -- the release web bundle in build/web, stamped with its build.
#
#   scripts/build_web.sh        KARTKA_BUILD defaults to the short HEAD sha
#
# The stamp is a <meta name="kartka-build" content="<sha>"> in index.html
# (and the KARTKA_BUILD dart define): scripts/deploy.sh reads it back from the
# wrapper to prove the served build is current. run.sh calls this too, so a
# launcher start re-stamps instead of dropping it. OAuth client ids come from
# ~/.config/kartka/oauth.json when it exists (--dart-define-from-file).
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OAUTH_DEFINES="${HOME}/.config/kartka/oauth.json"

main() {
    local build="${KARTKA_BUILD:-$(git -C "${ROOT}" rev-parse --short HEAD)}"
    local -a defines=("--dart-define=KARTKA_BUILD=${build}")
    if [[ -f "${OAUTH_DEFINES}" ]]; then
        defines+=("--dart-define-from-file=${OAUTH_DEFINES}")
    fi
    cd "${ROOT}"
    fvm flutter build web --release "${defines[@]}"
    local index="${ROOT}/build/web/index.html"
    sed -i '/<meta name="kartka-build"/d' "${index}"
    sed -i "0,/<head>/s||<head>\n  <meta name=\"kartka-build\" content=\"${build}\">|" "${index}"
    grep -q "name=\"kartka-build\" content=\"${build}\"" "${index}" ||
        { echo "error: could not stamp ${index}" >&2; exit 1; }
}

main "$@"
