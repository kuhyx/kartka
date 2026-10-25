#!/bin/bash
# Where does the eval Suwayomi's CPU go? Samples every JVM thread's CPU time
# from /proc twice, SECONDS apart (default 10, max 50: one action stays under
# 60 s), and prints CPU by thread group: GC, JIT compiler, request workers
# (Kotlin DefaultDispatcher / OkHttp / Javalin), database, other.
# Read-only; run it while a batch is loading the server:
#   eval_server_cpu.sh [SECONDS]
# Percentages are of one core (300 % is the unit's whole quota).
set -euo pipefail

readonly UNIT="${KARTKA_EVAL_UNIT:-kartka-suwayomi-eval}"
readonly SECS="${1:-10}"
if ! [[ ${SECS} =~ ^[0-9]+$ ]] || ((SECS < 1 || SECS > 50)); then
	echo "usage: $0 [SECONDS 1..50]" >&2
	exit 2
fi

pid="$(systemctl --user show "${UNIT}" -p MainPID --value)"
[[ ${pid} =~ ^[0-9]+$ && ${pid} -gt 0 ]] || {
	echo "${UNIT} is not running" >&2
	exit 1
}
tick="$(getconf CLK_TCK)"

# "<comm>\t<utime+stime ticks>" for every thread.
snapshot() {
	local dir stat rest
	local -a f
	for dir in /proc/"${pid}"/task/*; do
		[[ -r ${dir}/stat ]] || continue
		stat="$(<"${dir}/stat")"
		rest="${stat##*) }" # fields after "(comm)": state is f[0], utime f[11]
		read -r -a f <<<"${rest}"
		printf '%s\t%s\t%s\n' "${dir##*/}" "$(<"${dir}/comm")" "$((f[11] + f[12]))"
	done
}

group_of() {
	case "$1" in
	"GC Thread"* | "G1 "* | "VM Thread"* | "ParGC"*) echo "gc" ;;
	"C1 Compiler"* | "C2 Compiler"* | "Compiler"*) echo "jit" ;;
	DefaultDispatch* | OkHttp* | Jetty* | Javalin* | Scheduler-*) echo "requests" ;;
	*H2* | *Hikari* | *DB-Poo*) echo "database" ;;
	*) echo "other" ;;
	esac
}

declare -A before
while IFS=$'\t' read -r tid _ ticks; do before[${tid}]="${ticks}"; done < <(snapshot)
sleep "${SECS}"
declare -A used
total=0
while IFS=$'\t' read -r tid comm ticks; do
	delta=$((ticks - ${before[${tid}]:-0}))
	g="$(group_of "${comm}")"
	used[${g}]=$((${used[${g}]:-0} + delta))
	total=$((total + delta))
done < <(snapshot)

printf 'pid %s, %ss window, %s threads-ticks total\n' "${pid}" "${SECS}" "${total}"
for g in gc jit requests database other; do
	t="${used[${g}]:-0}"
	printf '%-9s %4s %% of a core  (%s %% of the JVM)\n' "${g}" \
		"$((t * 100 / (tick * SECS)))" "$((total ? t * 100 / total : 0))"
done
