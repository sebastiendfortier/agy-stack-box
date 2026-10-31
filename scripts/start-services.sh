#!/usr/bin/env bash
# Start the privately networked instance, then Obsidian + OpenRouter proxy inside it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_secrets
require_sif
RT="$(resolve_runtime)"

# Slim SIF expects large apps under state/apps
for req in \
  "$STATE_DIR/apps/antigravity-ide/Antigravity IDE/antigravity-ide" \
  "$STATE_DIR/apps/agy/agy" \
  "$STATE_DIR/apps/obsidian/Obsidian.AppImage"; do
  [[ -e "$req" ]] || die "missing $req — run ./scripts/fetch-apps.sh first"
done

if ! instance_running "$RT" "$INSTANCE_NAME"; then
  info "Starting instance '$INSTANCE_NAME' with private network..."
  # --net: separate netns (loopback services stay off the LAN).
  # bridge provides NAT egress for OpenRouter HTTPS.
  start_args=(
    instance start
    --net
    --network bridge
    --bind "$STATE_DIR:$STATE_IN_CONTAINER"
    --bind "$VAULT_HOST_PATH:$VAULT_IN_CONTAINER"
  )
  while IFS= read -r b; do
    [[ -n "$b" ]] && start_args+=(--bind "$b")
  done < <(display_binds)
  if [[ -n "${DISPLAY:-}" ]]; then
    start_args+=(--env "DISPLAY=$DISPLAY")
  fi
  if [[ -n "${XAUTHORITY:-}" ]]; then
    start_args+=(--env "XAUTHORITY=$XAUTHORITY")
  fi
  start_args+=(--env "HOME=$STATE_IN_CONTAINER/home")
  start_args+=(--env "CLOUD_CODE_URL=http://127.0.0.1:${PROXY_PORT}")
  start_args+=(--env "AGY_STATE=$STATE_IN_CONTAINER")
  start_args+=(--env "VAULT_PATH=$VAULT_IN_CONTAINER")

  if ! "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME"; then
    die "instance start with --net/--network bridge failed. On some hosts you need fakeroot/root or CNI packages. See README."
  fi
  echo "$INSTANCE_NAME" >"$STATE_DIR/instance.name"
else
  info "Instance '$INSTANCE_NAME' already running."
fi

# Start OpenRouter BYOK proxy if not healthy
if ! exec_in_instance "$RT" "$INSTANCE_NAME" \
  bash -lc "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null 2>&1"; then
  info "Starting OpenRouter BYOK proxy on 127.0.0.1:${PROXY_PORT}..."
  exec_in_instance "$RT" "$INSTANCE_NAME" \
    bash -lc "mkdir -p \"\$AGY_STATE/logs\" \"\$AGY_STATE/pids\" \"\$AGY_STATE/gemini/antigravity\"; nohup openrouter-proxy >>\"\$AGY_STATE/logs/proxy.log\" 2>&1 & echo \$! >\"\$AGY_STATE/pids/proxy.pid\""
  for _ in $(seq 1 30); do
    if exec_in_instance "$RT" "$INSTANCE_NAME" \
      bash -lc "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null 2>&1"; then
      break
    fi
    sleep 0.5
  done
  exec_in_instance "$RT" "$INSTANCE_NAME" \
    bash -lc "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null" \
    || die "proxy did not become healthy — see $STATE_DIR/logs/proxy.log"
fi
info "Proxy healthy on instance loopback :${PROXY_PORT}"

# Start Obsidian AppImage (GUI + Local REST API plugin in the vault)
if ! exec_in_instance "$RT" "$INSTANCE_NAME" \
  bash -lc "curl -fsS --max-time 2 http://127.0.0.1:${OBSIDIAN_REST_PORT}/ >/dev/null 2>&1 \
    || curl -fkSs --max-time 2 https://127.0.0.1:27124/ >/dev/null 2>&1"; then
  info "Starting Obsidian AppImage (vault=$VAULT_IN_CONTAINER)..."
  exec_in_instance "$RT" "$INSTANCE_NAME" \
    bash -lc "mkdir -p \"\$AGY_STATE/logs\" \"\$AGY_STATE/pids\"; nohup obsidian-stack \"\$VAULT_PATH\" >>\"\$AGY_STATE/logs/obsidian.log\" 2>&1 & echo \$! >\"\$AGY_STATE/pids/obsidian.pid\""
  info "Obsidian launched. First run: enable Local REST API in the vault if needed."
  info "REST should listen on 127.0.0.1:${OBSIDIAN_REST_PORT} (insecure) inside the instance only."
else
  info "Obsidian REST already responding on instance loopback."
fi

info "Services up. Next: ./scripts/start-ide.sh  or  ./scripts/start-cli.sh"
