#!/bin/bash
# Credentials and the Caddy site block. Sourced by install.sh after common.sh.
#
# Every service on this edge owns exactly one snippet in sites/ (the shared
# Caddyfile only imports them). The edge serves every public service, so a
# snippet that fails validation is rolled back before anything reloads.

# Generate the password once (0600, outside the repo) and keep its bcrypt hash
# beside it, so a rerun writes a byte-identical snippet and skips the reload.
ensure_credentials() {
	SUWAYOMI_HOST="${SUWAYOMI_HOST:-}"
	SUWAYOMI_USER="${SUWAYOMI_USER:-}"
	SUWAYOMI_PASSWORD=""
	SUWAYOMI_BCRYPT=""
	if [[ -f ${ENV_FILE} ]]; then
		local want_host="${SUWAYOMI_HOST}"
		# shellcheck source=/dev/null
		source "${ENV_FILE}"
		[[ -n ${want_host} ]] && SUWAYOMI_HOST="${want_host}"
	fi
	SUWAYOMI_HOST="${SUWAYOMI_HOST:-${DEFAULT_HOST}}"
	SUWAYOMI_USER="${SUWAYOMI_USER:-kuhy}"
	if [[ -z ${SUWAYOMI_PASSWORD} ]]; then
		# URL-safe alphabet: the Dart client and curl never need to escape it.
		SUWAYOMI_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n')"
		SUWAYOMI_BCRYPT=""
		log "generated a new password"
	fi
	if [[ -z ${SUWAYOMI_BCRYPT} ]]; then
		# stdin, not --plaintext: keeps the password out of every process list.
		SUWAYOMI_BCRYPT="$(printf '%s\n' "${SUWAYOMI_PASSWORD}" |
			docker exec -i "${CADDY_CONTAINER}" caddy hash-password)"
		[[ ${SUWAYOMI_BCRYPT} == \$2* ]] || die "caddy hash-password returned no bcrypt hash"
	fi
	mkdir -p "$(dirname "${ENV_FILE}")"
	chmod 700 "$(dirname "${ENV_FILE}")"
	local tmp
	tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
	{
		printf '# Kartka Suwayomi credentials -- written by deploy/suwayomi/install.sh. Never commit.\n'
		printf 'SUWAYOMI_URL=%q\n' "https://${SUWAYOMI_HOST}"
		printf 'SUWAYOMI_HOST=%q\n' "${SUWAYOMI_HOST}"
		printf 'SUWAYOMI_USER=%q\n' "${SUWAYOMI_USER}"
		printf 'SUWAYOMI_PASSWORD=%q\n' "${SUWAYOMI_PASSWORD}"
		printf 'SUWAYOMI_BCRYPT=%q\n' "${SUWAYOMI_BCRYPT}"
	} >"${tmp}"
	chmod 600 "${tmp}"
	if cmp -s "${tmp}" "${ENV_FILE}"; then
		rm -f "${tmp}"
	else
		mv "${tmp}" "${ENV_FILE}"
	fi
	ok "credentials in ${ENV_FILE} (0600)"
}

render_snippet() {
	printf '# Managed by kartka deploy/suwayomi/install.sh -- do not edit by hand.\n'
	printf '# Password only (Caddy basic auth); the server itself binds loopback.\n'
	printf '%s {\n' "${SUWAYOMI_HOST}"
	printf '\tbasic_auth {\n\t\t%s %s\n\t}\n' "${SUWAYOMI_USER}" "${SUWAYOMI_BCRYPT}"
	printf '\treverse_proxy 127.0.0.1:%s\n}\n' "${SUWAYOMI_PORT}"
}

caddy_in() { docker exec "${CADDY_CONTAINER}" caddy "$@" --config "${CADDYFILE_IN_CONTAINER}"; }

configure_caddy() {
	docker ps --format '{{.Names}}' | grep -qx "${CADDY_CONTAINER}" ||
		die "Caddy container '${CADDY_CONTAINER}' is not running"
	[[ -d ${CADDY_SITES_DIR} ]] || die "no Caddy sites dir at ${CADDY_SITES_DIR}"
	local desired backup=""
	desired="$(render_snippet)"
	if [[ -f ${SNIPPET} && "$(<"${SNIPPET}")" == "${desired}" ]]; then
		ok "Caddy snippet already current: ${SNIPPET}"
		return 0
	fi
	if [[ -f ${SNIPPET} ]]; then
		backup="$(mktemp "${SNIPPET}.bak.XXXXXX")"
		cp -p "${SNIPPET}" "${backup}"
	fi
	printf '%s\n' "${desired}" >"${SNIPPET}"
	if ! caddy_in validate >/dev/null 2>&1; then
		if [[ -n ${backup} ]]; then mv "${backup}" "${SNIPPET}"; else rm -f "${SNIPPET}"; fi
		die "Caddy rejected the new snippet; rolled back, edge untouched"
	fi
	[[ -n ${backup} ]] && rm -f "${backup}"
	caddy_in reload >/dev/null 2>&1 || die "caddy reload failed -- docker logs ${CADDY_CONTAINER} | tail"
	ok "Caddy reloaded with ${SNIPPET}"
}
