#!/usr/bin/env bash
# In-image: run antigravity-add-model desktop proxy against AGY_STATE.
set -euo pipefail
STATE="${AGY_STATE:-/agy-state}"
DATA="$STATE/gemini/antigravity"
PORT="${PROXY_PORT:-50999}"
mkdir -p "$DATA"
# Prefer PATH node (host overlay or SIF /usr/local); allow NODE_BIN override.
NODE="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
if [[ -z "$NODE" || ! -x "$NODE" ]]; then
  echo "error: node not found (install Node on the host or in the SIF)" >&2
  exit 1
fi
exec "$NODE" /opt/antigravity-add-model/scripts/desktop-service.mjs run \
  --port "$PORT" \
  --data-dir "$DATA"
