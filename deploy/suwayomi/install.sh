#!/bin/bash
# install.sh -- self-hosted Suwayomi-Server for Kartka, next to SyncYomi.
#
# Installs the pinned Suwayomi-Server release (its bundled JRE included) under
# ~/services/suwayomi, runs it as a systemd *user* unit bound to 127.0.0.1:4567,
# adds the Keiyoushi extension store, and publishes it through the host's
# existing Caddy edge (container gitea-caddy) at https://suwayomi.kuhy.duckdns.org
# behind basic auth. Credentials are generated once into
# ~/.config/kartka/suwayomi.env (0600) and never enter the repo.
#
# Run as your normal user, never under sudo: it needs no root at all (linger
# is already on; the *.kuhy.duckdns.org wildcard already resolves; 80/443 are
# already open). Idempotent: a rerun with nothing to change touches nothing.
#
# Usage:
#   ./install.sh                install or update, then return (no long wait)
#   ./install.sh --verify-only  check the running deployment end to end
#   ./install.sh --help
#
# Env overrides (vmbox uses these): SUWAYOMI_HOST, CADDY_CONTAINER,
# CADDY_SITES_DIR, CADDYFILE_IN_CONTAINER, KARTKA_SUWAYOMI_ENV, VERIFY_INSECURE=1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/app.sh
source "${SCRIPT_DIR}/lib/app.sh"
# shellcheck source=lib/edge.sh
source "${SCRIPT_DIR}/lib/edge.sh"
# shellcheck source=lib/verify.sh
source "${SCRIPT_DIR}/lib/verify.sh"

usage() {
	sed -n '2,/^$/p' "$0" | sed -E 's/^# ?//'
}

install_cmd() {
	[[ ${EUID} -ne 0 ]] || die "run as your normal user, not root (sudo strips the user bus)"
	require_cmds curl tar jq sha256sum docker systemctl loginctl cmp ip pacman
	require_kcef_pkgs
	ensure_credentials
	fetch_release
	install_release
	install_unit
	wait_ready
	ensure_store
	configure_caddy
	log "installed. Check it end to end: ${SCRIPT_DIR}/install.sh --verify-only"
}

main() {
	case "${1:-}" in
	"") install_cmd ;;
	--verify-only) verify_cmd ;;
	-h | --help) usage ;;
	*) die "unknown argument '$1' (try --help)" ;;
	esac
}

main "$@"
