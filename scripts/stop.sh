#!/usr/bin/env bash
# Stop Obsidian/proxy inside the instance, then stop the instance.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

RT="$(resolve_runtime)"
if [[ -f "$SECRETS_FILE" ]]; then
  load_secrets
else
  INSTANCE_NAME="${INSTANCE_NAME:-$INSTANCE_NAME_DEFAULT}"
fi

if instance_running "$RT" "$INSTANCE_NAME"; then
  info "Stopping services inside '$INSTANCE_NAME'..."
  exec_in_instance "$RT" "$INSTANCE_NAME" bash -lc '
    for name in obsidian proxy; do
      f="$AGY_STATE/pids/${name}.pid"
      if [[ -f "$f" ]]; then
        pid=$(cat "$f" || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          kill "$pid" 2>/dev/null || true
          sleep 0.5
          kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$f"
      fi
    done
    pkill -f "/opt/obsidian/Obsidian" 2>/dev/null || true
    pkill -f "desktop-service.mjs" 2>/dev/null || true
    true
  ' || true
  info "Stopping instance..."
  "$RT" instance stop "$INSTANCE_NAME" || true
else
  info "Instance '$INSTANCE_NAME' is not running."
fi
rm -f "$STATE_DIR/instance.name"
info "Stopped."
