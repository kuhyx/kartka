#!/bin/bash
# unit_flags_test.sh -- static check of the Suwayomi unit and its readback.
# Read-only, safe on the host: it only greps repo files.
#
# KCEF is on (decision 2026-10-29): sources whose extension needs a WebView
# work, and the ranking puts them low instead. FlareSolverr is pinned off by
# -D flags, so a web-UI toggle cannot turn challenge solving on: Kartka never
# solves a challenge (docs/DOCS-contracts-webview.md §2).

set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
readonly DIR
readonly UNIT="${DIR}/suwayomi.service"
readonly VERIFY="${DIR}/lib/verify.sh"
readonly COMMON="${DIR}/lib/common.sh"
readonly APP="${DIR}/lib/app.sh"
readonly PREFIX='-Dsuwayomi.tachidesk.config.server.'
FAILS=0

# expect <file> <fixed string> <what>
expect() {
	if grep -qF -- "$2" "$1"; then echo "OK   $3"; else
		echo "FAIL $3 (no '$2' in ${1##*/})"
		FAILS=$((FAILS + 1))
	fi
}

# reject <file> <fixed string> <what>
reject() {
	if grep -qF -- "$2" "$1"; then
		echo "FAIL $3 ('$2' still in ${1##*/})"
		FAILS=$((FAILS + 1))
	else echo "OK   $3"; fi
}

main() {
	expect "${UNIT}" "${PREFIX}kcefEnabled=true " "unit turns KCEF on"
	reject "${UNIT}" "${PREFIX}kcefEnabled=false" "unit no longer turns KCEF off"
	expect "${UNIT}" "${PREFIX}flareSolverrEnabled=false " "unit pins FlareSolverr off"
	expect "${UNIT}" "${PREFIX}flareSolverrAsResponseFallback=false " \
		"unit pins the FlareSolverr response fallback off"
	expect "${UNIT}" "${PREFIX}authMode=NONE " "unit keeps Caddy as the only auth gate"
	expect "${UNIT}" "${PREFIX}ip=127.0.0.1 " "unit keeps the loopback bind"
	# CEF needs an X display; the unit gives it a private Xvfb, never the desktop.
	expect "${UNIT}" 'ExecStart=/usr/bin/xvfb-run -n 99 -s "-nolisten tcp -nolisten local ' \
		"unit runs the server under a private Xvfb"
	expect "${UNIT}" 'UnsetEnvironment=DISPLAY XAUTHORITY WAYLAND_DISPLAY' \
		"unit still hides the desktop session from the server"
	expect "${COMMON}" 'readonly KCEF_PKGS=(xorg-server-xvfb xorg-xauth nss nspr ' \
		"installer lists the packages KCEF needs"
	# shellcheck disable=SC2016 # the literal source text is what is grepped
	expect "${APP}" 'pacman -T "${KCEF_PKGS[@]}"' "installer checks them without root"
	expect "${VERIFY}" '_SYSTEMD_INVOCATION_ID=' "--verify-only reads this start's journal"
	expect "${VERIFY}" 'Failed to set up CEF|ContentMainRun failed' \
		"--verify-only fails a CEF that did not start"
	expect "${VERIFY}" 'bin/kcef/jcef_helper' "--verify-only wants the CEF helpers running"
	expect "${VERIFY}" 'flareSolverrEnabled flareSolverrAsResponseFallback' \
		"--verify-only reads the FlareSolverr settings back"
	expect "${VERIFY}" '"true/NONE"' "--verify-only expects KCEF on, auth NONE"
	expect "${VERIFY}" '"false/false" "no challenge solving' \
		"--verify-only expects both FlareSolverr settings off"
	((FAILS == 0)) || {
		echo "${FAILS} check(s) failed" >&2
		exit 1
	}
	echo "all checks passed"
}

main "$@"
