#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
export HOME="${HOME:-${AGY_STATE:-/agy-state}/home}"
APP="/opt/antigravity-ide/Antigravity IDE"
if [[ -u "$APP/chrome-sandbox" ]]; then
  exec "$APP/antigravity-ide" "$@"
fi
export ELECTRON_DISABLE_SANDBOX=1
exec "$APP/antigravity-ide" --disable-gpu-sandbox --no-sandbox "$@"
