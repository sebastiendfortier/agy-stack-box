#!/usr/bin/env bash
# In-image: run antigravity-add-model desktop proxy against AGY_STATE.
set -euo pipefail
STATE="${AGY_STATE:-/agy-state}"
DATA="$STATE/gemini/antigravity"
PORT="${PROXY_PORT:-50999}"
mkdir -p "$DATA"
# This SIF's Node 22 is at /usr/local/bin, which the host /usr overlay hides.
# Rebuilt images put it at /apps/node. state/opt-node is that same tree, already
# bind-mounted with AGY_STATE. Never fall through to host /bin/node (v12).
NODE=""
_seen=""
for cand in \
  "${NODE_BIN:-}" \
  /apps/node/bin/node \
  /usr/local/bin/node \
  "$STATE/opt-node/bin/node"
do
  [[ -n "$cand" && -x "$cand" ]] || continue
  case ":${_seen}:" in
    *":${cand}:"*) continue ;;
  esac
  _seen="${_seen:+${_seen}:}${cand}"
  _major="$("$cand" -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
  if [[ "${_major}" -ge 18 ]]; then
    NODE="$cand"
    break
  fi
done
if [[ -z "$NODE" ]]; then
  echo "error: no Node >= 18 (tried NODE_BIN, /apps/node, /usr/local, $STATE/opt-node). Host /usr overlay hides the SIF copy; host /bin/node is too old." >&2
  exit 1
fi
exec "$NODE" /opt/antigravity-add-model/scripts/desktop-service.mjs run \
  --port "$PORT" \
  --data-dir "$DATA"
