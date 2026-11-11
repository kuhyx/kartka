#!/bin/bash
# shellcheck source-path=SCRIPTDIR

# ============================================================================
# check_apk_signer.sh [apk] -- exit 0 when the release APK is signed with the
# shared release key (android/key.properties) and carries the debug -> release
# rotation lineage that lets it install over the debug-signed Pixel app.
# Default apk: build/app/outputs/flutter-apk/app-release.apk.
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
# shellcheck source=lib/signing.sh
source "${ROOT}/scripts/lib/signing.sh"

check_apk_signer "${1:-${ROOT}/build/app/outputs/flutter-apk/app-release.apk}"
