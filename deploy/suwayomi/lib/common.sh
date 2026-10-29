#!/bin/bash
# Shared constants and helpers for deploy/suwayomi. Sourced, never run: it
# inherits the caller's strict mode.
# shellcheck disable=SC2034 # constants are read by the sourcing scripts

# --- Pinned release (newest stable; bump both lines together) ---------------
# Upstream: https://github.com/Suwayomi/Suwayomi-Server/releases
readonly SUWAYOMI_VERSION="v2.4.2366"
readonly SUWAYOMI_SHA256="7a469f8c820e65305f795d61f1776c783919884531497b587bdff898a7e0fa73"
readonly SUWAYOMI_TARBALL="Suwayomi-Server-${SUWAYOMI_VERSION}-linux-x64.tar.gz"
readonly SUWAYOMI_RELEASE_URL="https://github.com/Suwayomi/Suwayomi-Server/releases/download/${SUWAYOMI_VERSION}/${SUWAYOMI_TARBALL}"

# Keiyoushi's store, in the form Suwayomi v2.4 stores it (it rewrites the
# older raw.githubusercontent .../index.min.json URL to this one).
readonly KEIYOUSHI_INDEX="https://github.com/keiyoushi/extensions/raw/repo/index.pb"

# --- Layout (the unit file hard-codes these via %h; keep them in step) ------
readonly SUWAYOMI_HOME="${HOME}/services/suwayomi"
readonly APP_ROOT="${SUWAYOMI_HOME}/app"
readonly APP_DIR="${APP_ROOT}/${SUWAYOMI_VERSION}"
readonly DATA_DIR="${SUWAYOMI_HOME}/data"
readonly SUWAYOMI_PORT=4567
readonly SUWAYOMI_LOCAL="http://127.0.0.1:${SUWAYOMI_PORT}"
readonly UNIT_NAME="suwayomi.service"
readonly UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
# KCEF: the private Xvfb the unit runs under, plus the shared libraries the
# downloaded CEF bundle links against (a bare Arch install lacks them).
readonly KCEF_PKGS=(xorg-server-xvfb xorg-xauth nss nspr alsa-lib at-spi2-core
	libcups libxcomposite libxcursor libxdamage libxi libxtst libxrender)
readonly CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/kartka/suwayomi"

# Credentials live outside the repo, 0600; never committed.
readonly ENV_FILE="${KARTKA_SUWAYOMI_ENV:-${XDG_CONFIG_HOME:-${HOME}/.config}/kartka/suwayomi.env}"

# --- Existing host edge (overridable so vmbox can stand up its own copy) ----
readonly CADDY_CONTAINER="${CADDY_CONTAINER:-gitea-caddy}"
readonly CADDY_SITES_DIR="${CADDY_SITES_DIR:-${HOME}/services/gitea/sites}"
readonly CADDYFILE_IN_CONTAINER="${CADDYFILE_IN_CONTAINER:-/etc/caddy/Caddyfile}"
readonly SNIPPET="${CADDY_SITES_DIR}/suwayomi.caddy"
readonly DEFAULT_HOST="suwayomi.kuhy.duckdns.org"

log() { printf '[suwayomi] %s\n' "$*"; }
ok() { printf '[suwayomi] OK   %s\n' "$*"; }
fail() { printf '[suwayomi] FAIL %s\n' "$*" >&2; }
die() {
	fail "$*"
	exit 1
}

require_cmds() {
	local c
	for c in "$@"; do
		command -v "${c}" >/dev/null 2>&1 || die "missing command '${c}' (pacman -S ${c})"
	done
}

# Load the credential file into SUWAYOMI_HOST/USER/PASSWORD/BCRYPT.
load_env() {
	[[ -f ${ENV_FILE} ]] || die "no credentials at ${ENV_FILE} -- run install.sh first"
	# shellcheck source=/dev/null
	source "${ENV_FILE}"
	: "${SUWAYOMI_HOST:?missing in ${ENV_FILE}}" "${SUWAYOMI_USER:?}" "${SUWAYOMI_PASSWORD:?}"
}

# POST one GraphQL document to the local (loopback) endpoint; prints the body.
# Usage: local_gql '{ aboutServer { version } }'
local_gql() {
	jq -n --arg q "$1" '{query: $q}' |
		curl -sS --max-time 20 -H 'Content-Type: application/json' \
			--data-binary @- "${SUWAYOMI_LOCAL}/api/graphql"
}
