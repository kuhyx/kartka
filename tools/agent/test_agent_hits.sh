#!/bin/bash
# Unit test for `kartka_agent.sh fault` history and `hits` (no agent needed):
#   tools/agent/test_agent_hits.sh
# Two live checks read a `page waited on open` entry as a real miss when a
# `slow-images:800` fault was on (11:12Z, 11:52Z on 2026-11-27): `hits`
# must tag every reader probe entry with the fault active at its time.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
AGENT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kartka_agent.sh"
readonly AGENT
HOME="$(mktemp -d)"
export HOME
trap 'rm -rf "$HOME"' EXIT
readonly LOG="$HOME/.local/share/kartka-agent/files/diagnostics/kartka-diagnostics.jsonl"
readonly HIST="$HOME/.local/share/kartka-agent/faults.history"

# fault/clear append one history line each: "<UTC ms ISO> <rules|none>".
"$AGENT" fault '*' slow-images:800 >/dev/null
"$AGENT" fault clear >/dev/null
[[ "$(wc -l <"$HIST")" -eq 2 ]] || fail "history has $(wc -l <"$HIST") lines, want 2"
grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}\.[0-9]{3}Z \{"\*":"slow-images:800"\}$' \
  <(sed -n 1p "$HIST") || fail "bad first line: $(sed -n 1p "$HIST")"
grep -qE 'Z none$' <(sed -n 2p "$HIST") || fail "bad clear line: $(sed -n 2p "$HIST")"

# A fixed history around three probe entries and one unrelated entry.
cat >"$HIST" <<'EOF'
2026-11-27T11:11:00.000Z {"*":"slow-images:800"}
2026-11-27T11:13:00.000Z none
EOF
mkdir -p "$(dirname "$LOG")"
cat >"$LOG" <<'EOF'
{"at":"2026-11-27T11:10:00.000Z","kind":"reader.pagewait","error":"ReaderLoadException: ReaderProbe: mangadex page waited on turn from mangadex.network"}
{"at":"2026-11-27T11:12:09.655Z","kind":"reader.pagewait","error":"ReaderLoadException: ReaderProbe: mangadex page waited on open from mangadex.network"}
{"at":"2026-11-27T11:12:30.000Z","kind":"perf.jank","error":"screen=/browse frames=1"}
{"at":"2026-11-27T11:14:00.000Z","kind":"perf.slow","error":"slow wait: reader.page"}
EOF

got="$("$AGENT" hits 2026-11-27T11:11:30Z)"
want='2026-11-27T11:12:09.655Z reader.pagewait [fault {"*":"slow-images:800"}] ReaderLoadException: ReaderProbe: mangadex page waited on open from mangadex.network
2026-11-27T11:14:00.000Z perf.slow [clean] slow wait: reader.page'
[[ "$got" == "$want" ]] || fail "hits since 11:11:30Z:
got:
$got
want:
$want"

# Before the first history line nobody knows: [unrecorded], never [clean].
[[ "$("$AGENT" hits 2026-11-27T11:00:00Z | head -1)" == *" [unrecorded] "* ]] ||
  fail "an entry before the history must be unrecorded"
rm "$HIST"
[[ "$("$AGENT" hits 2026-11-27T11:00:00Z | grep -c '\[unrecorded\]')" -eq 3 ]] ||
  fail "entries without a history must be unrecorded"
# No log: an error, never a pass.
rm "$LOG"
if "$AGENT" hits 2026-11-27T11:00:00Z >/dev/null 2>&1; then
  fail "hits without a diagnostics log must fail"
fi
echo "PASS test_agent_hits"
