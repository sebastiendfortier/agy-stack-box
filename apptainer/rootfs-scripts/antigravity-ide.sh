#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
# Keep Singularity --home (real login home) for file pickers / Open Folder.
BIN="$(agy-resolve-app ide)"
APP="$(agy-resolve-app ide-dir)"
if [[ -u "$APP/chrome-sandbox" ]]; then
  exec "$BIN" "$@"
fi
export ELECTRON_DISABLE_SANDBOX=1
exec "$BIN" --disable-gpu-sandbox --no-sandbox "$@"
