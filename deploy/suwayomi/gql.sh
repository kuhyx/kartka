#!/bin/bash
# gql.sh -- send one GraphQL document to the deployed Suwayomi through Caddy,
# with the credentials from ~/.config/kartka/suwayomi.env. Prints the JSON body.
#
# Usage: ./gql.sh <file.graphql> [variables-json]
#   ./gql.sh ../../test/fixtures/suwayomi/about_server.graphql
#   ./gql.sh .../fetch_source_manga.graphql '{"source":"2499283573021220255","query":"berserk","page":1}'
# GQL_LOCAL=1 targets 127.0.0.1 directly (bypasses Caddy; for debugging only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

main() {
	[[ $# -ge 1 && -f $1 ]] || die "usage: gql.sh <file.graphql> [variables-json]"
	local vars="${2:-{\}}" url auth=()
	jq -e . >/dev/null <<<"${vars}" || die "variables are not valid JSON: ${vars}"
	load_env
	if [[ ${GQL_LOCAL:-0} == 1 ]]; then
		url="${SUWAYOMI_LOCAL}/api/graphql"
	else
		url="https://${SUWAYOMI_HOST}/api/graphql"
		auth=(-u "${SUWAYOMI_USER}:${SUWAYOMI_PASSWORD}")
	fi
	jq -n --rawfile q "$1" --argjson v "${vars}" '{query: $q, variables: $v}' |
		curl -fsS --max-time 50 "${auth[@]}" -H 'Content-Type: application/json' \
			--data-binary @- "${url}"
}

main "$@"
