#!/usr/bin/env bash
# Launch the Antigravity app under a supervisor that records how it died.
#
# The app can disappear with no trace: no "Shutting down" line in main.log, no
# Crashpad dump, no core (ulimit -c is 0 by default). This wrapper logs the exit
# status and signal so the next occurrence is diagnosable.
#
# Run it inside tmux so a dropped ThinLinc session does not kill the supervisor:
#   tmux new -s agy 'scripts/agy-app-watch.sh'
#
# Exit codes: 128+N means killed by signal N (9=SIGKILL, 11=SIGSEGV, 15=SIGTERM).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${AGY_APP_WATCH_LOG:-$HOME/agy-app-exits.log}"
RESTART_DELAY_SEC="${AGY_APP_WATCH_DELAY:-3}"

# Cores are disabled by default; core_pattern writes core.%e.%h.%s.%p to the cwd.
ulimit -c unlimited 2>/dev/null || true

log() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

log "=== supervisor start (pid=$$, ulimit -c=$(ulimit -c)) ==="

while :; do
    log "launching agy-app"
    "$SCRIPT_DIR/agy-app" "$@"
    rc=$?

    if (( rc > 128 )); then
        sig=$(( rc - 128 ))
        log "exit=$rc signal=$sig ($(kill -l "$sig" 2>/dev/null || echo unknown))"
    else
        log "exit=$rc (no signal)"
    fi

    # A clean exit is the user quitting: stop supervising.
    if (( rc == 0 )); then
        log "=== clean exit, supervisor stopping ==="
        break
    fi

    log "restarting in ${RESTART_DELAY_SEC}s"
    sleep "$RESTART_DELAY_SEC"
done
