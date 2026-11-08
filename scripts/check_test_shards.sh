#!/bin/bash

# ============================================================================
# Fail unless the shard manifest (scripts/test_shards.txt) covers every
# test/**/*_test.dart exactly once and names nothing that does not exist.
#
# The whole suite no longer fits one 60 s call, so the gate runs it as shards
# (scripts/test_shard.sh <id>), one stamped step each. A test file missing
# from every shard would silently drop out of the gate; this is the guard.
#
# Manifest lines: `<id> <path-or-glob>...`; `#` starts a comment. A path is a
# directory (every *_test.dart under it) or a file glob.
#
# Usage: scripts/check_test_shards.sh [--list]   (--list: print shard ids)
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly MANIFEST="${TEST_SHARDS_MANIFEST:-${ROOT}/scripts/test_shards.txt}"

die() {
    echo "check_test_shards: $*" >&2
    exit 1
}

# Print the test files one shard covers, one per line (paths relative to ROOT).
shard_files() {
    local entry out
    shopt -s nullglob
    for entry in "$@"; do
        if [[ -d "${ROOT}/${entry}" ]]; then
            out="$(cd "${ROOT}" && find "${entry}" -name '*_test.dart')"
        else
            out="$(cd "${ROOT}" && for f in ${entry}; do [[ -e "${f}" ]] && echo "${f}"; done || true)"
        fi
        [[ -n "${out}" ]] || die "'${entry}' matches no test files"
        echo "${out}"
    done
}

# Print `<id> <entries...>` lines without comments or blanks.
manifest_lines() {
    [[ -f "${MANIFEST}" ]] || die "missing manifest ${MANIFEST}"
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${MANIFEST}"
}

main() {
    if [[ "${1:-}" == "--list" ]]; then
        manifest_lines | awk '{print $1}'
        return 0
    fi
    local all dupes missing line id
    local -a entries
    local covered
    covered="$(mktemp)"
    COVERED_TMP="${covered}"
    trap 'rm -f "${COVERED_TMP}"' EXIT
    while read -r line; do
        id="${line%% *}"
        [[ "${line}" == *[[:space:]]* ]] || die "shard '${id}' lists no paths"
        read -ra entries <<<"${line#"${id}"}"
        local found
        found="$(shard_files "${entries[@]}")"
        [[ -n "${found}" ]] || die "shard '${id}' matches no test files"
        echo "${found}" >>"${covered}"
    done < <(manifest_lines)

    all="$(cd "${ROOT}" && find test -name '*_test.dart' | sort)"
    missing="$(comm -13 <(sort -u "${covered}") <(echo "${all}"))"
    dupes="$(sort "${covered}" | uniq -d)"
    [[ -z "${missing}" ]] || die "test files in no shard:"$'\n'"${missing}"
    [[ -z "${dupes}" ]] || die "test files in more than one shard:"$'\n'"${dupes}"
    echo "check_test_shards: $(wc -l <<<"${all}") test files, each in exactly one shard"
}

main "$@"
