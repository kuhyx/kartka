#!/bin/bash
# ============================================================================
# Offline test for install.sh: systemctl and uv are stubs on PATH, HOME is a
# temp dir holding a copy of tools/errors at ~/src/kartka/tools/errors.
# Touches no real unit, no user bus, no RTDB.
# Run: tools/errors/systemd/test_install.sh
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
readonly HERE
readonly TOOL="${HERE%/systemd}"
SANDBOX=""
FAILS=0

cleanup() {
	if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then rm -rf "$SANDBOX"; fi
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*"
	FAILS=$((FAILS + 1))
}

# Stubs append every call to $SANDBOX/calls. `systemctl is-active` and
# `is-enabled` succeed only when $SANDBOX/active exists.
make_stubs() {
	mkdir -p "$SANDBOX/bin"
	cat >"$SANDBOX/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >>"$STUB_DIR/calls"
case "$2" in
    is-active | is-enabled) [[ -e "$STUB_DIR/active" ]] ;;
    *) exit 0 ;;
esac
EOF
	cat >"$SANDBOX/bin/uv" <<'EOF'
#!/bin/bash
echo "uv $*" >>"$STUB_DIR/calls"
EOF
	chmod +x "$SANDBOX/bin/systemctl" "$SANDBOX/bin/uv"
}

# A fresh HOME with tools/errors copied where the units expect it.
fresh() {
	SANDBOX="$(mktemp -d)"
	mkdir -p "$SANDBOX/home/src/kartka/tools"
	cp -r "$TOOL" "$SANDBOX/home/src/kartka/tools/errors"
	make_stubs
	: >"$SANDBOX/calls"
}

# Runs install.sh (from the copy, or from $2) with $1; prints its output.
run_install() {
	local script="${2:-$SANDBOX/home/src/kartka/tools/errors/systemd/install.sh}"
	HOME="$SANDBOX/home" XDG_CONFIG_HOME="" PATH="$SANDBOX/bin:$PATH" \
		STUB_DIR="$SANDBOX" bash "$script" "$@"
}

units() { echo "$SANDBOX/home/.config/systemd/user"; }

test_install() {
	fresh
	run_install "" >/dev/null || fail "install exited non-zero"
	for u in kartka-errors.service kartka-errors.timer; do
		cmp -s "$TOOL/systemd/$u" "$(units)/$u" || fail "$u not installed"
	done
	grep -q "systemctl --user daemon-reload" "$SANDBOX/calls" || fail "no daemon-reload"
	grep -q "systemctl --user enable --now kartka-errors.timer" "$SANDBOX/calls" ||
		fail "timer not enabled"
	grep -q "uv sync --frozen" "$SANDBOX/calls" || fail "venv not synced"
	grep -q "ExecStart=%h/src/kartka/tools/errors/run.sh ingest" \
		"$(units)/kartka-errors.service" || fail "unit runs the wrong command"

	: >"$SANDBOX/calls"
	run_install "" >/dev/null || fail "second install exited non-zero"
	! grep -q daemon-reload "$SANDBOX/calls" || fail "unchanged units reloaded"
	cleanup
}

test_verify() {
	fresh
	run_install --verify-only >/dev/null 2>&1 && fail "verify passed with nothing installed"
	run_install "" >/dev/null
	run_install --verify-only >/dev/null 2>&1 && fail "verify passed with the timer inactive"
	touch "$SANDBOX/active"
	run_install --verify-only >/dev/null || fail "verify failed on a good install"
	grep -q "uv run --frozen --quiet --project" "$SANDBOX/calls" || fail "verify did not start the tool"
	echo "# edited" >>"$(units)/kartka-errors.timer"
	run_install --verify-only >/dev/null 2>&1 && fail "verify passed with a stale unit"
	cleanup
}

test_wrong_checkout() {
	fresh
	local out
	if out="$(run_install "" "$TOOL/systemd/install.sh" 2>&1)"; then
		fail "installed from a checkout the units do not point at"
	fi
	[[ "$out" == *"run from"* ]] || fail "wrong-checkout message missing: $out"
	[[ ! -e "$(units)/kartka-errors.timer" ]] || fail "units written from the wrong checkout"
	cleanup
}

test_uninstall() {
	fresh
	run_install "" >/dev/null
	run_install --uninstall >/dev/null || fail "uninstall exited non-zero"
	[[ ! -e "$(units)/kartka-errors.timer" ]] || fail "timer unit left behind"
	grep -q "systemctl --user disable --now kartka-errors.timer" "$SANDBOX/calls" ||
		fail "timer not disabled"
	run_install --bogus >/dev/null 2>&1 && fail "unknown argument accepted"
	run_install --help | grep -q "Usage:" || fail "no usage"
	cleanup
}

test_install
test_verify
test_wrong_checkout
test_uninstall

if ((FAILS > 0)); then
	echo "$FAILS check(s) failed"
	exit 1
fi
echo "test_install.sh: all checks passed"
