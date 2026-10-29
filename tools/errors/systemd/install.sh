#!/bin/bash
# install.sh -- the Kartka error collector's systemd *user* units.
#
# Installs, into ~/.config/systemd/user:
#   kartka-errors.service  one ingest: /kartka/errors -> ~/src/kartka/TODO-fixme.md
#   kartka-errors.timer    every 15 minutes (Persistent: catches up after sleep)
# The units run tools/errors/run.sh from ~/src/kartka, so the repo must be
# checked out there. Needs uv and the kartka-source-eval sign-in session
# (tools/errors/run.sh ingest names the seed command when it is missing).
# No root. Idempotent.
#
# Usage:
#   ./install.sh                install or update the units, enable the timer
#   ./install.sh --verify-only  check the units are current and the timer runs
#   ./install.sh --uninstall    stop and remove both units
#   ./install.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly SCRIPT_DIR
readonly TOOL_DIR="${SCRIPT_DIR%/systemd}"
readonly EXPECTED_DIR="${HOME}/src/kartka/tools/errors"
readonly UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
readonly UNITS=(kartka-errors.service kartka-errors.timer)
readonly TIMER=kartka-errors.timer

log() { echo "==> $*"; }
ok() { echo "  ok: $*"; }
die() {
	echo "install.sh: $*" >&2
	exit 1
}

usage() { sed -n '2,/^$/p' "$0" | sed -E 's/^# ?//'; }

uv_bin() { command -v uv || echo "${HOME}/.local/bin/uv"; }

require() {
	[[ ${EUID} -ne 0 ]] || die "run as your normal user, not root (sudo strips the user bus)"
	local c
	for c in systemctl cmp install; do
		command -v "${c}" >/dev/null || die "missing command: ${c}"
	done
	[[ -x "$(uv_bin)" ]] || die "missing uv"
	[[ ${TOOL_DIR} == "${EXPECTED_DIR}" ]] ||
		die "run from ${EXPECTED_DIR} (the units point there), not ${TOOL_DIR}"
}

install_units() {
	mkdir -p "${UNIT_DIR}"
	local f changed=0
	for f in "${UNITS[@]}"; do
		if ! cmp -s "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}"; then
			install -m 0644 "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}"
			changed=1
			ok "installed ${f}"
		fi
	done
	((changed == 0)) || systemctl --user daemon-reload
	systemctl --user enable --now "${TIMER}" >/dev/null
	ok "timer enabled: ${TIMER}"
}

sync_venv() {
	"$(uv_bin)" sync --frozen --project "${TOOL_DIR}" --quiet
	ok "kartka-errors venv in sync"
}

verify_cmd() {
	require
	local f
	for f in "${UNITS[@]}"; do
		cmp -s "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}" || die "${f} not installed or stale"
	done
	ok "units installed and current"
	systemctl --user is-enabled --quiet "${TIMER}" || die "${TIMER} not enabled"
	systemctl --user is-active --quiet "${TIMER}" || die "${TIMER} not active"
	ok "timer enabled and active"
	"${TOOL_DIR}/run.sh" --help >/dev/null || die "kartka-errors does not start"
	ok "kartka-errors starts"
}

uninstall_cmd() {
	systemctl --user disable --now "${TIMER}" >/dev/null 2>&1 || true
	local f
	for f in "${UNITS[@]}"; do
		rm -f "${UNIT_DIR}/${f}"
	done
	systemctl --user daemon-reload
	ok "units removed (state in ~/.local/state/kartka-errors kept)"
}

main() {
	case "${1:-}" in
	"")
		require
		install_units
		sync_venv
		log "done; check with ${SCRIPT_DIR}/install.sh --verify-only"
		;;
	--verify-only) verify_cmd ;;
	--uninstall) uninstall_cmd ;;
	-h | --help) usage ;;
	*) die "unknown argument '$1' (try --help)" ;;
	esac
}

main "$@"
