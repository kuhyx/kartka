#!/bin/bash
# install.sh -- the Kartka source evaluator's systemd *user* units.
#
# Installs, into ~/.config/systemd/user:
#   kartka-suwayomi-eval.service      its OWN Suwayomi on 127.0.0.1:4590
#                                     (rootDir ~/.local/share/kartka-source-eval/
#                                     suwayomi), started only with the jobs below
#   kartka-source-eval-probe.{service,timer}  uptime probe 4x a day
#   kartka-source-eval-full.{service,timer}   full run + RTDB publish, weekly
# The live Suwayomi (:4567, deploy/suwayomi) is never touched: the evaluator
# installs every candidate extension (~570) into the server it talks to.
#
# Needs the live deploy's pinned release (~/services/suwayomi/app/current,
# from deploy/suwayomi/install.sh) for the JRE and jar, uv, curl, jq, and the
# repo checked out at ~/src/kartka (the units run tools/source_eval from there).
# No root. Idempotent.
#
# Usage:
#   ./install.sh                install or update the units, enable the timers
#   ./install.sh --verify-only  check units + timers, start the eval server once
#   ./install.sh --run-now      also start the full run now (hours; --no-block)
#   ./install.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly SCRIPT_DIR
readonly EVAL_DIR="${SCRIPT_DIR%/systemd}"
readonly EXPECTED_DIR="${HOME}/src/kartka/tools/source_eval"
readonly UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
readonly APP_CURRENT="${HOME}/services/suwayomi/app/current"
readonly SERVER_UNIT="kartka-suwayomi-eval.service"
readonly UNITS=(
	"${SERVER_UNIT}"
	kartka-source-eval-probe.service kartka-source-eval-probe.timer
	kartka-source-eval-full.service kartka-source-eval-full.timer
)
readonly TIMERS=(kartka-source-eval-probe.timer kartka-source-eval-full.timer)

log() { echo "==> $*"; }
ok() { echo "  ok: $*"; }
die() {
	echo "install.sh: $*" >&2
	exit 1
}

usage() { sed -n '2,/^$/p' "$0" | sed -E 's/^# ?//'; }

require() {
	[[ ${EUID} -ne 0 ]] || die "run as your normal user, not root (sudo strips the user bus)"
	local c
	for c in curl jq systemctl systemd-run cmp; do
		command -v "${c}" >/dev/null || die "missing command: ${c}"
	done
	command -v uv >/dev/null || [[ -x ${HOME}/.local/bin/uv ]] || die "missing uv"
	[[ ${EVAL_DIR} == "${EXPECTED_DIR}" ]] ||
		die "run from ${EXPECTED_DIR} (the units point there), not ${EVAL_DIR}"
	[[ -x ${APP_CURRENT}/jre/bin/java && -f ${APP_CURRENT}/bin/Suwayomi-Server.jar ]] ||
		die "no Suwayomi release at ${APP_CURRENT}: run deploy/suwayomi/install.sh first"
}

# A unit must never point the evaluator at the live server.
check_no_live() {
	local f
	for f in "${UNITS[@]}"; do
		! grep -q 'KARTKA_SUWAYOMI_URL=.*:4567' "${SCRIPT_DIR}/${f}" ||
			die "${f} points at the live Suwayomi (:4567)"
	done
	ok "no unit targets the live :4567"
}

install_units() {
	mkdir -p "${UNIT_DIR}" "${HOME}/.local/share/kartka-source-eval/suwayomi"
	# An earlier hand-run transient unit of the same name blocks the real one.
	systemctl --user reset-failed "${SERVER_UNIT}" 2>/dev/null || true
	local f changed=0
	for f in "${UNITS[@]}"; do
		if ! cmp -s "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}"; then
			install -m 0644 "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}"
			changed=1
			ok "installed ${f}"
		fi
	done
	((changed == 0)) || systemctl --user daemon-reload
	systemctl --user enable --now "${TIMERS[@]}" >/dev/null 2>&1
	ok "timers enabled: ${TIMERS[*]}"
}

sync_venv() {
	local uv_bin
	uv_bin="$(command -v uv || echo "${HOME}/.local/bin/uv")"
	"${uv_bin}" sync --frozen --project "${EVAL_DIR}" --quiet
	ok "source_eval venv in sync"
}

verify_cmd() {
	require
	check_no_live
	local f t
	for f in "${UNITS[@]}"; do
		cmp -s "${SCRIPT_DIR}/${f}" "${UNIT_DIR}/${f}" || die "${f} not installed or stale"
	done
	ok "units installed and current"
	for t in "${TIMERS[@]}"; do
		systemctl --user is-active --quiet "${t}" || die "${t} not active"
	done
	ok "timers active"
	# Start the eval server as a dependency of a one-off waiter; it stops
	# again on its own afterwards (StopWhenUnneeded).
	systemd-run --user --wait --quiet --collect \
		-p "Requires=${SERVER_UNIT}" -p "After=${SERVER_UNIT}" \
		"${SCRIPT_DIR}/eval_server_ready.sh" || die "eval server did not come up"
	ok "eval Suwayomi answers on 127.0.0.1:4590 with the Keiyoushi store"
}

main() {
	case "${1:-}" in
	"" | --run-now)
		require
		check_no_live
		install_units
		sync_venv
		if [[ ${1:-} == --run-now ]]; then
			systemctl --user start --no-block kartka-source-eval-full.service
			ok "full run started (journalctl --user -u kartka-source-eval-full -f)"
		fi
		log "done; check with ${SCRIPT_DIR}/install.sh --verify-only"
		;;
	--verify-only) verify_cmd ;;
	-h | --help) usage ;;
	*) die "unknown argument '$1' (try --help)" ;;
	esac
}

main "$@"
