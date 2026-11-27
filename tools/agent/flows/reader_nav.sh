#!/bin/bash
# Reader navigation shared by the timed reader flows (f6, f7): sourced, never
# run. Needs lib.sh, AGENT, SOURCE, TITLE and CHAPTER_ROW.
# shellcheck disable=SC2154 # AGENT, SOURCE, TITLE, CHAPTER_ROW: the flow's

# The reader controls' header: "<chapter name> | <page> / <count>".
readonly HEADER='^#[0-9]+ group "(.+) \| ([0-9]+) / ([0-9]+)"'

now_ms() { date +%s%3N; }

# Prints "<chapter>|<page>|<count>" from the controls' header, or nothing.
# A downloaded chapter's header carries " | Downloaded" after the name: cut,
# so the name field never holds a "|".
header() {
  drive tree 2>/dev/null | sed -nE "s@${HEADER}.*@\1|\2|\3@p" |
    sed -E 's@ \| Downloaded\|@|@' | head -n 1
}

# The header, waiting up to 10 s for it (the controls show after a tap).
wait_header() {
  local h deadline=$(($(now_ms) + 10000))
  while (($(now_ms) < deadline)); do
    h="$(header)"
    [[ -n "$h" ]] && { echo "$h"; return 0; }
  done
  return 1
}

# Back pops the detail and source screens, Escape the reader (whose Back
# hides with its controls); a tree read mid-transition can miss the tabs,
# so it asks again before failing.
to_tabs() {
  local i
  for ((i = 0; i < 8; i++)); do
    on_tabs && return 0
    if drive tree 2>/dev/null | grep -E '^#[0-9]+ button "Back" ' >/dev/null; then
      drive tap Back >/dev/null 2>&1 || true
    else
      drive key Escape >/dev/null 2>&1 || true
    fi
    sleep 0.5
  done
  # A route opened by URL (SOURCE_ID) has no page under it to pop to.
  on_tabs || drive eval "location.hash = '#/library'" >/dev/null 2>&1 || true
  sleep 1
  on_tabs || fail "the tab shell never appeared"
}

# Starts the agent, opens chapter row $CHAPTER_ROW of "$TITLE" from
# $SOURCE (a manga outside the library) and shows the reader controls;
# sets h to their header.
open_reader() {
  step "start the isolated agent instance"
  check "$AGENT" start >/dev/null
  to_tabs

  step "open \"$TITLE\" from $SOURCE"
  if [[ -n "${SOURCE_ID:-}" ]]; then
    # A source the Browse grid does not show (its language is not picked,
    # and the picked languages sync): open its route directly.
    check drive eval "location.hash = '#/browse/source/' +
      encodeURIComponent('$SOURCE_ID')" >/dev/null
  else
    check drive tap Browse >/dev/null
    check drive wait "$SOURCE" --timeout 20 >/dev/null
    # The source grid settles once every provider listed: tap after that.
    sleep 2
    check drive tap "$SOURCE" >/dev/null
  fi
  check drive wait "$TITLE" --timeout 20 >/dev/null
  check drive tap "$TITLE" >/dev/null
  check drive wait "Show details" --timeout 20 >/dev/null
  if drive tree | grep -qE '"[^"]*In library'; then
    fail "\"$TITLE\" is in the library: pick a manga outside it (F6_TITLE)"
  fi

  step "open chapter row $CHAPTER_ROW"
  # Chapter row N of the detail list, once the list is in (up to ~10 s).
  chapter_row() {
    drive tree | sed -nE 's/^#[0-9]+ button "((Vol\. [0-9]+ )?Ch(\.|apter )[^"]+)" \[tap\].*/\1/p' |
      sed -n "${CHAPTER_ROW}p"
  }
  local chapter=""
  local i
  for ((i = 0; i < 20 && ${#chapter} == 0; i++)); do
    chapter="$(chapter_row)"
    [[ -n "$chapter" ]] || sleep 0.5
  done
  [[ -n "$chapter" ]] || fail "no chapter row $CHAPTER_ROW"
  check drive tap "$chapter" >/dev/null
  # The reader's full-screen page button, not the "Previous" slot: that one
  # is named by the chapter list, and waiting for it hid the list wait.
  local opened=0
  for ((i = 0; i < 100 && opened == 0; i++)); do
    if drive tree 2>/dev/null | grep -E '^#[0-9]+ button "" \[tap\] @0,0 ' >/dev/null; then
      opened=1
    fi
  done
  ((opened)) || fail "\"$chapter\" never opened"
  check drive tap-xy 700 450 >/dev/null
  h="$(wait_header)" || fail "the reader controls never showed"
}
