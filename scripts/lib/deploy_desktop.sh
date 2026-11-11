#!/bin/bash

# ============================================================================
# deploy_desktop.sh -- the desktop half of scripts/deploy.sh (sourced, never
# run). Uses SRC, PORT, SHA, WAIT_SECS, log and die from deploy.sh.
#
# The desktop app is build/web served by the wrapper on 127.0.0.1:47391
# (the launcher runs run.sh, which rebuilds and stamps it through
# scripts/build_web.sh). The check reads the stamp the wrapper serves.
# ============================================================================

WRAPPER_PID=""

served_build() {
    curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/" 2>/dev/null |
        sed -n 's/.*name="kartka-build" content="\([0-9a-f]*\)".*/\1/p' | head -1
}

port_answers() { curl -fsS --max-time 3 -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null; }

# setsid gives the wrapper its own process group, so one kill stops fvm, dart
# and anything they spawned.
wrapper_start() {
    (cd "${SRC}/desktop" && fvm dart pub get >/dev/null)
    (cd "${SRC}/desktop" && exec setsid fvm dart run bin/kartka_desktop.dart \
        --web-root "${SRC}/build/web" --no-browser >/dev/null 2>&1) &
    WRAPPER_PID=$!
    trap wrapper_stop EXIT
    local waited=0
    until port_answers; do
        ((waited < WAIT_SECS)) || die "wrapper did not answer on ${PORT} in ${WAIT_SECS} s"
        sleep 1
        waited=$((waited + 1))
    done
}

wrapper_stop() {
    [[ -n "${WRAPPER_PID}" ]] || return 0
    kill -TERM -- "-${WRAPPER_PID}" 2>/dev/null || kill -TERM "${WRAPPER_PID}" 2>/dev/null || true
    wait "${WRAPPER_PID}" 2>/dev/null || true
    WRAPPER_PID=""
    local waited=0
    while port_answers; do
        ((waited < 10)) || die "port ${PORT} still answers after stopping our wrapper"
        sleep 1
        waited=$((waited + 1))
    done
}

desktop_check() {
    local foreign=no served
    if port_answers; then
        foreign=yes
    else
        wrapper_start
    fi
    served="$(served_build)"
    if [[ "${foreign}" == no ]]; then wrapper_stop; fi
    [[ "${served}" == "${SHA}" ]] ||
        die "desktop serves build ${served:-unstamped}, want ${SHA}"
    if [[ "${foreign}" == yes ]]; then
        log "desktop: ${SHA} on disk; restart needed (a running wrapper was left alone)"
    else
        log "desktop: ${SHA} served on ${PORT}"
    fi
}
