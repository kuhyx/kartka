#!/bin/bash

# ============================================================================
# Gate step: dart analyze (infos fatal) and the format check, the CLI's two
# static checks from CLAUDE.md. Capped like test_shard.sh when run from an
# agent session.
# ============================================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
pre=()
if [[ -x "${CAPPED}" && -z "${CI:-}" ]]; then pre=("${CAPPED}"); fi
export CAP_MEM="${CAP_MEM:-4G}" CAP_CPU_PCT="${CAP_CPU_PCT:-20}"

"${pre[@]}" fvm dart analyze --fatal-infos
"${pre[@]}" fvm dart format --set-exit-if-changed lib test desktop

# The deploy script against fakes (no phone, no port 47391).
scripts/test_deploy.sh
