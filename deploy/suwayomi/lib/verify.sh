#!/bin/bash
# --verify-only: prove the deployment from the outside in. Every check prints
# OK/FAIL; the function returns non-zero if any failed. Sourced by install.sh.
#
# Requests go to 127.0.0.1:443 with --resolve, so this tests Caddy itself
# rather than DNS or the router's hairpin NAT.

VERIFY_FAILS=0
check() {
	if [[ $1 == "$2" ]]; then ok "$3"; else
		fail "$3 (got '$1', want '$2')"
		VERIFY_FAILS=$((VERIFY_FAILS + 1))
	fi
}

# edge_post <auth: none|good|bad> <graphql>  -> prints "<http_code> <body>"
edge_post() {
	local auth=() tls=()
	case "$1" in
	good) auth=(-u "${SUWAYOMI_USER}:${SUWAYOMI_PASSWORD}") ;;
	bad) auth=(-u "${SUWAYOMI_USER}:wrong-${RANDOM}") ;;
	esac
	# Sandbox only: vmbox serves *.localhost from Caddy's internal CA.
	[[ ${VERIFY_INSECURE:-0} == 1 ]] && tls=(-k)
	jq -n --arg q "$2" '{query: $q}' |
		curl -sS --max-time 15 "${tls[@]}" "${auth[@]}" \
			--resolve "${SUWAYOMI_HOST}:443:127.0.0.1" \
			-H 'Content-Type: application/json' --data-binary @- \
			-w '\n%{http_code}' "https://${SUWAYOMI_HOST}/api/graphql" 2>/dev/null |
		{
			body="$(cat)"
			code="${body##*$'\n'}"
			printf '%s %s\n' "${code}" "${body%$'\n'*}"
		}
}

# A freshly added subdomain needs a few seconds for its ACME certificate, so
# retry the authorised call for at most ~40 s before judging anything.
wait_edge() {
	local i out
	for ((i = 0; i < 8; i++)); do
		out="$(edge_post good '{ aboutServer { version } }' || true)"
		[[ ${out%% *} == 200 ]] && return 0
		sleep 5
	done
	log "edge still not answering 200: ${out:-no response}"
}

lan_ip() { ip -4 -o route get 1.1.1.1 2>/dev/null | sed -nE 's/.* src ([0-9.]+).*/\1/p'; }

verify_cmd() {
	load_env
	check "$(systemctl --user is-active "${UNIT_NAME}" 2>/dev/null || true)" active "unit ${UNIT_NAME} active"
	check "$(systemctl --user is-enabled "${UNIT_NAME}" 2>/dev/null || true)" enabled "unit ${UNIT_NAME} enabled"
	check "$(local_gql '{ aboutServer { version } }' | jq -r '.data.aboutServer.version' 2>/dev/null)" \
		"${SUWAYOMI_VERSION}" "loopback GraphQL reports ${SUWAYOMI_VERSION}"

	local settings
	settings="$(local_gql '{ settings { ip port authMode systemTrayEnabled initialOpenInBrowserEnabled kcefEnabled flareSolverrEnabled flareSolverrAsResponseFallback } }')"
	check "$(jq -r '.data.settings | "\(.ip):\(.port)"' <<<"${settings}")" "127.0.0.1:${SUWAYOMI_PORT}" "server binds loopback only"
	check "$(jq -r '.data.settings | "\(.systemTrayEnabled)/\(.initialOpenInBrowserEnabled)"' <<<"${settings}")" \
		"false/false" "no tray icon, no browser on the desktop"
	check "$(jq -r '.data.settings | "\(.kcefEnabled)/\(.authMode)"' <<<"${settings}")" \
		"true/NONE" "KCEF on for WebView extensions; Caddy is the only auth gate"
	check "$(jq -r '.data.settings | "\(.flareSolverrEnabled)/\(.flareSolverrAsResponseFallback)"' <<<"${settings}")" \
		"false/false" "no challenge solving (FlareSolverr and its fallback off)"
	check "$(local_gql '{ extensionStores { nodes { indexUrl } } }' |
		jq -r --arg u "${KEIYOUSHI_INDEX}" '[.data.extensionStores.nodes[].indexUrl] | index($u) != null')" \
		true "Keiyoushi store configured"

	local ip
	ip="$(lan_ip)"
	if [[ -n ${ip} ]]; then
		check "$(curl -s -o /dev/null --max-time 3 -w '%{http_code}' "http://${ip}:${SUWAYOMI_PORT}/" || true)" \
			000 "LAN ${ip}:${SUWAYOMI_PORT} refused (Caddy cannot be bypassed)"
	fi

	wait_edge
	local out
	out="$(edge_post none '{ aboutServer { version } }')"
	check "${out%% *}" 401 "edge refuses a request without credentials"
	out="$(edge_post bad '{ aboutServer { version } }')"
	check "${out%% *}" 401 "edge refuses a wrong password"
	out="$(edge_post good '{ aboutServer { version } }')"
	check "${out%% *}" 200 "edge accepts the password"
	check "$(jq -r '.data.aboutServer.version' <<<"${out#* }" 2>/dev/null)" "${SUWAYOMI_VERSION}" \
		"https://${SUWAYOMI_HOST}/api/graphql answers through Caddy"

	((VERIFY_FAILS == 0)) || die "${VERIFY_FAILS} check(s) failed"
	ok "all checks passed"
}
