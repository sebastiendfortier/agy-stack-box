#!/usr/bin/env bash
# In-image: run antigravity-add-model desktop proxy against AGY_STATE.
set -euo pipefail
STATE="${AGY_STATE:-/agy-state}"
DATA="$STATE/gemini/antigravity"
PORT="${PROXY_PORT:-50999}"
mkdir -p "$DATA"
# Prefer /apps/node (survives host /usr overlay). Host Node 12 breaks optional chaining.
NODE="${NODE_BIN:-}"
if [[ -z "$NODE" || ! -x "$NODE" ]]; then
  for cand in \
    /apps/node/bin/node \
    /opt/agy-stack/node/bin/node \
    /usr/local/bin/node; do
    if [[ -x "$cand" ]]; then NODE="$cand"; break; fi
  done
fi
if [[ -z "$NODE" || ! -x "$NODE" ]]; then
  NODE="$(command -v node 2>/dev/null || true)"
fi
if [[ -z "$NODE" || ! -x "$NODE" ]]; then
  echo "error: node not found (expected /apps/node/bin/node in the SIF)" >&2
  exit 1
fi
_major="$("$NODE" -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [[ "${_major}" -lt 18 ]]; then
  echo "error: node $("$NODE" -v 2>/dev/null) at $NODE is too old; need >=18 under /apps/node" >&2
  exit 1
fi
exec "$NODE" /opt/antigravity-add-model/scripts/desktop-service.mjs run \
  --port "$PORT" \
  --data-dir "$DATA"
