#!/bin/bash

# ============================================================================
# Run one gate shard of the flutter suite (see scripts/test_shards.txt).
#
# Each shard stays well under the 60 s per-call cap. Inside this machine's
# agent sessions it runs through ~/.claude/scripts/capped.sh (4 GiB, 40 % CPU
# unless CAP_MEM / CAP_CPU_PCT say otherwise); CI and kuhy's shell run bare.
# First verifies the manifest still covers every test file, so a stale list
# fails here instead of silently dropping tests from the gate.
#
# Usage: scripts/test_shard.sh <shard-id>      (ids: check_test_shards.sh --list)
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly MANIFEST="${ROOT}/scripts/test_shards.txt"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"

main() {
    [[ $# -eq 1 ]] || { echo "usage: test_shard.sh <shard-id>" >&2; exit 2; }
    local id="$1" line
    cd "${ROOT}"
    "${ROOT}/scripts/check_test_shards.sh" >/dev/null
    line="$(sed -e 's/#.*//' "${MANIFEST}" | awk -v id="${id}" '$1 == id')"
    [[ -n "${line}" ]] || { echo "test_shard: unknown shard '${id}'" >&2; exit 2; }
    local -a paths cmd=(fvm flutter test --no-pub --reporter=compact)
    read -ra paths <<<"${line#"${id}"}"
    if [[ -x "${CAPPED}" && -z "${CI:-}" ]]; then
        CAP_MEM="${CAP_MEM:-4G}" CAP_CPU_PCT="${CAP_CPU_PCT:-40}" exec "${CAPPED}" "${cmd[@]}" "${paths[@]}"
    fi
    exec "${cmd[@]}" "${paths[@]}"
}

main "$@"
