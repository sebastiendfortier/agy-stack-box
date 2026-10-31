#!/usr/bin/env bash
# In-image: run antigravity-add-model desktop proxy against AGY_STATE.
set -euo pipefail
STATE="${AGY_STATE:-/agy-state}"
DATA="$STATE/gemini/antigravity"
PORT="${PROXY_PORT:-50999}"
NODE="${NODE_BIN:-/usr/local/bin/node}"
mkdir -p "$DATA"
export HOME="${HOME:-$STATE/home}"
export PATH="/usr/local/bin:${PATH:-/usr/bin:/bin}"
exec "$NODE" /opt/antigravity-add-model/scripts/desktop-service.mjs run \
  --port "$PORT" \
  --data-dir "$DATA"
