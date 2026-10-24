#!/bin/bash
# vmbox_guest_edge.sh -- run INSIDE a vmbox guest, never on the host. Stands
# up a copy of the host's Caddy edge (caddy:2.8, host networking, a root
# Caddyfile that only imports sites/*.caddy, one pre-existing neighbour site)
# so install.sh can be exercised against the same shape it meets on the host.
#
# Prereqs in the guest: docker running and usable by this user.
# The neighbour site proves a Suwayomi change never breaks other services.

set -euo pipefail

readonly EDGE_DIR="${HOME}/services/gitea"
readonly SITES="${EDGE_DIR}/sites"

main() {
	[[ -f /etc/vmbox-guest || ${USER} == arch ]] || {
		echo "refusing: this only runs inside a vmbox guest" >&2
		exit 1
	}
	mkdir -p "${SITES}"
	printf '%s\n' '# Managed by setup_gitea.sh -- do not edit by hand.' \
		'import /etc/caddy/sites/*.caddy' >"${EDGE_DIR}/Caddyfile"
	printf '%s\n' 'neighbour.localhost {' '	respond "neighbour ok" 200' '}' >"${SITES}/neighbour.caddy"
	if ! docker ps --format '{{.Names}}' | grep -qx gitea-caddy; then
		docker rm -f gitea-caddy >/dev/null 2>&1 || true
		docker run -d --name gitea-caddy --network host --restart unless-stopped \
			-v "${EDGE_DIR}/Caddyfile:/etc/caddy/Caddyfile" \
			-v "${SITES}:/etc/caddy/sites" caddy:2.8 >/dev/null
	fi
	sleep 2
	curl -sk --resolve neighbour.localhost:443:127.0.0.1 https://neighbour.localhost/
	echo
}

main "$@"
