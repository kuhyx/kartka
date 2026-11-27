#!/bin/bash
# Unit test for reader_nav.sh's header parsing (no agent needed):
#   tools/agent/flows/test_reader_nav.sh
# A downloaded chapter's header reads "<name> | Downloaded | p / n"; the
# parsed name must not carry the mark, or f6's `read name page count`
# feeds "Downloaded" to arithmetic (unbound variable).
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
# shellcheck source-path=SCRIPTDIR source=reader_nav.sh
source "$(dirname "${BASH_SOURCE[0]}")/reader_nav.sh"

expect() {
  local tree=$1 want=$2 got
  drive() { printf '%s\n' "$tree"; }
  got="$(header)"
  [[ "$got" == "$want" ]] || fail "header of <$tree>: got <$got>, want <$want>"
}

expect '#1705 group "Ch. 25.1 | 1 / 20" [focused] @0,0 1400x913' 'Ch. 25.1|1|20'
expect '#1870 group "Ch. 184 - Narita News Flash | Downloaded | 1 / 4" [focused] @0,0 1400x913' \
  'Ch. 184 - Narita News Flash|1|4'
expect '#3 group "" @0,0 1400x913' ''
echo "PASS test_reader_nav"
