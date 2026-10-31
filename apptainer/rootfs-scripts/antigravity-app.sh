#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
BIN="$(agy-resolve-app app)"
APP="$(agy-resolve-app app-dir)"
if [[ -u "$APP/chrome-sandbox" ]]; then
  exec "$BIN" "$@"
fi
export ELECTRON_DISABLE_SANDBOX=1
exec "$BIN" --disable-gpu-sandbox --no-sandbox "$@"
