#!/bin/bash

# ============================================================================
# Gate step: the desktop/ wrapper package (separate pubspec), analyzed and
# tested. Capped like test_shard.sh when run from an agent session.
# ============================================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../desktop"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
pre=()
if [[ -x "${CAPPED}" && -z "${CI:-}" ]]; then pre=("${CAPPED}"); fi
export CAP_MEM="${CAP_MEM:-4G}" CAP_CPU_PCT="${CAP_CPU_PCT:-40}"

"${pre[@]}" fvm dart analyze --fatal-infos
"${pre[@]}" fvm dart test --reporter=compact
