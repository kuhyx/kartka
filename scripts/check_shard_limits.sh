#!/bin/bash

# ============================================================================
# Fail unless the gate stays inside kuhy's resource ceiling (4 GiB, 20 % CPU
# per capped.sh call) and the pre-commit manual steps match the shard list.
#
# Checks: every gate script defaults CAP_MEM to 4G and CAP_CPU_PCT to 20;
# test_shard.sh caps `flutter test` concurrency (-j) to bound peak memory; and
# .pre-commit-config.yaml has exactly one gate-test-<id> step per shard in
# scripts/test_shards.txt (a shard without a step never runs in the gate).
#
# Usage: scripts/check_shard_limits.sh
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly SCRIPTS=(test_shard.sh gate_static.sh gate_desktop.sh)
readonly MAX_MEM="4G" MAX_CPU="20"
fail=0

bad() {
    echo "check_shard_limits: $*" >&2
    fail=1
}

check_defaults() {
    local s
    for s in "${SCRIPTS[@]}"; do
        grep -q "CAP_MEM:-${MAX_MEM}}" "${ROOT}/scripts/${s}" || bad "${s}: CAP_MEM default is not ${MAX_MEM}"
        grep -q "CAP_CPU_PCT:-${MAX_CPU}}" "${ROOT}/scripts/${s}" || bad "${s}: CAP_CPU_PCT default is not ${MAX_CPU}"
    done
    grep -Eq -- '--concurrency=[0-9]+|-j[ =]?[0-9]+' "${ROOT}/scripts/test_shard.sh" ||
        bad "test_shard.sh sets no flutter test concurrency (-j)"
}

check_steps() {
    local shards steps
    shards="$("${ROOT}/scripts/check_test_shards.sh" --list | sort)"
    steps="$(grep -Eo 'id: gate-test-[A-Za-z0-9]+' "${ROOT}/.pre-commit-config.yaml" | sed 's/id: gate-test-//' | sort)"
    [[ "${shards}" == "${steps}" ]] || bad "shards ($(echo "${shards}" | tr '\n' ' ')) != pre-commit steps ($(echo "${steps}" | tr '\n' ' '))"
}

main() {
    check_defaults
    check_steps
    ((fail == 0)) || exit 1
    echo "check_shard_limits: ok"
}

main "$@"
