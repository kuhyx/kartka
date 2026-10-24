#!/bin/bash
# Wait for the evaluator's own Suwayomi (127.0.0.1:4590) to answer GraphQL,
# then make sure the Keiyoushi extension store is configured there.
# ExecStartPre of both evaluator jobs; idempotent; never touches :4567.
set -euo pipefail

readonly EVAL_URL="${KARTKA_SUWAYOMI_URL:-http://127.0.0.1:4590}"
readonly KEIYOUSHI_INDEX="https://github.com/keiyoushi/extensions/raw/repo/index.pb"
readonly WAIT_SECONDS="${EVAL_WAIT_SECONDS:-180}"

die() {
	echo "eval_server_ready: $*" >&2
	exit 1
}

gql() {
	jq -n --arg q "$1" '{query: $q}' |
		curl -sS --max-time 20 -H 'Content-Type: application/json' \
			--data-binary @- "${EVAL_URL}/api/graphql"
}

[[ ${EVAL_URL} != *:4567* ]] || die "refusing the live Suwayomi (${EVAL_URL})"

deadline=$((SECONDS + WAIT_SECONDS))
until gql '{ aboutServer { version } }' 2>/dev/null | jq -e '.data.aboutServer.version' >/dev/null; do
	((SECONDS < deadline)) || die "${EVAL_URL} did not answer within ${WAIT_SECONDS}s"
	sleep 2
done

if ! gql '{ extensionStores { nodes { indexUrl } } }' | grep -qF "\"${KEIYOUSHI_INDEX}\""; then
	out="$(gql "mutation { addExtensionStore(input: {indexUrl: \"${KEIYOUSHI_INDEX}\"}) { clientMutationId } }")"
	jq -e '.errors == null' <<<"${out}" >/dev/null || die "addExtensionStore failed: ${out}"
	echo "eval_server_ready: added the Keiyoushi store"
fi
echo "eval_server_ready: ${EVAL_URL} ready"
