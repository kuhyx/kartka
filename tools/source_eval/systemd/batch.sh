#!/bin/bash
# batch.sh -- sourced by weekly.sh and probe.sh: run one source-eval
# subcommand as a loop of short batches. Every call gets --budget seconds
# (a hard wall-clock limit inside the evaluator) and exits 10 while there is
# more to do; `timeout` is only the backstop for a bug in that guarantee.
#
# Knobs (environment): KARTKA_EVAL_BUDGET (50 s), KARTKA_EVAL_HARD_STOP
# (58 s, the backstop), KARTKA_EVAL_MAX_BATCHES (2000 calls per step).

readonly MORE_WORK=10
readonly TIMED_OUT=124
readonly BUDGET="${KARTKA_EVAL_BUDGET:-50}"
readonly HARD_STOP="${KARTKA_EVAL_HARD_STOP:-58}"
readonly MAX_BATCHES="${KARTKA_EVAL_MAX_BATCHES:-2000}"

# One evaluator call, never longer than HARD_STOP seconds.
eval_once() {
	timeout --kill-after=1 "${HARD_STOP}" \
		uv run --frozen --project "${HERE:?}" source-eval "$@"
}

# eval_batches <subcommand args...>: call until it is done (exit 0).
eval_batches() {
	local n=0 rc
	while ((n < MAX_BATCHES)); do
		n=$((n + 1))
		rc=0
		eval_once "$@" --budget "${BUDGET}" || rc=$?
		case "${rc}" in
		0) return 0 ;;
		"${MORE_WORK}") ;;
		"${TIMED_OUT}") echo "batch.sh: '$1' hit the ${HARD_STOP} s hard stop; resuming" >&2 ;;
		*) return "${rc}" ;;
		esac
	done
	echo "batch.sh: '$1' still unfinished after ${MAX_BATCHES} batches" >&2
	return 1
}
