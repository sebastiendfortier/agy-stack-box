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

# AGY_NET_MODE=host (default): share host netns; proxy/Obsidian still bind 127.0.0.1
#   (LAN-safe, no sudo, OpenRouter egress works).
# AGY_NET_MODE=bridge: Singularity CNI private net (strict). On Ubuntu Singularity CE
#   this often needs: sudo singularity instance start ... and may still lack egress.
NET_MODE="${AGY_NET_MODE:-host}"

if ! instance_running "$RT" "$INSTANCE_NAME"; then
  info "Starting instance '$INSTANCE_NAME' (AGY_NET_MODE=$NET_MODE)..."
  start_args=(instance start)
  case "$NET_MODE" in
    bridge)
      start_args+=(--net --network bridge)
      # systemd-resolved stub is unreachable inside a netns
      DNS_FILE="$STATE_DIR/resolv.conf"
      if [[ ! -f "$DNS_FILE" ]]; then
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >"$DNS_FILE"
      fi
      start_args+=(--bind "$DNS_FILE:/etc/resolv.conf")
      ;;
    host) ;;
    *) die "AGY_NET_MODE must be host or bridge (got: $NET_MODE)" ;;
  esac
  while IFS= read -r b; do
    [[ -n "$b" ]] && start_args+=(--bind "$b")
  done < <(all_instance_binds)
  while IFS= read -r b; do
    [[ -n "$b" ]] && start_args+=("$b")
  done < <(instance_home_args)
  instance_runtime_env start_args
  info "Host tools: AGY_HOST_OS_TOOLS=${AGY_HOST_OS_TOOLS:-1} AGY_HOST_PATH_BINDS=${AGY_HOST_PATH_BINDS:-1} (PATH/modules passed through)"

  if [[ "$NET_MODE" == bridge ]]; then
    if ! "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME"; then
      if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        info "unprivileged bridge start failed; retrying with passwordless sudo..."
        sudo "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME" \
          || die "bridge start failed. On HPC (no sudo) use default AGY_NET_MODE=host."
      else
        die "bridge CNI start failed and sudo is unavailable (typical on HPC). Use AGY_NET_MODE=host (default)."
      fi
    fi
  else
    "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME" \
      || die "instance start failed"
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
    bash -lc "mkdir -p \"\$AGY_STATE/logs\" \"\$AGY_STATE/pids\" \"\$AGY_STATE/gemini/antigravity\"; nohup env PROXY_PORT=\"\$PROXY_PORT\" OPENROUTER_API_KEY=\"\$OPENROUTER_API_KEY\" AGY_STATE=\"\$AGY_STATE\" openrouter-proxy >>\"\$AGY_STATE/logs/proxy.log\" 2>&1 & echo \$! >\"\$AGY_STATE/pids/proxy.pid\""
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
  info "Starting Obsidian AppImage (vault=$VAULT_HOST_PATH)..."
  exec_in_instance "$RT" "$INSTANCE_NAME" \
    bash -lc "mkdir -p \"\$AGY_STATE/logs\" \"\$AGY_STATE/pids\"
      # Avoid pkill -f matching this shell; kill prior AppImage by pid file if present.
      if [[ -f \"\$AGY_STATE/pids/obsidian.pid\" ]]; then
        kill \"\$(cat \"\$AGY_STATE/pids/obsidian.pid\")\" 2>/dev/null || true
        sleep 0.5
      fi
      nohup obsidian-stack \"\${VAULT_HOST_PATH:-\$VAULT_PATH}\" >>\"\$AGY_STATE/logs/obsidian.log\" 2>&1 & echo \$! >\"\$AGY_STATE/pids/obsidian.pid\""
  info "Obsidian launched with preconfigured vault $VAULT_HOST_PATH"
  info "REST should listen on 127.0.0.1:${OBSIDIAN_REST_PORT} (insecure) inside the instance only."
else
  info "Obsidian REST already responding on instance loopback."
fi

info "Services up. Next: ./scripts/start-ide.sh  or  ./scripts/start-cli.sh"
