#!/usr/bin/env bash
# Launch Antigravity App 2.0 (multi-agent desktop, not the IDE) inside the instance.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_secrets
RT="$(resolve_runtime)"
instance_running "$RT" "$INSTANCE_NAME" || die "instance not running — ./scripts/start-services.sh first"

exec_in_instance "$RT" "$INSTANCE_NAME" \
  bash -lc "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null" \
  || die "proxy not healthy — ./scripts/start-services.sh"

[[ -x "$STATE_DIR/apps/antigravity-app/Antigravity-x64/antigravity" ]] \
  || die "missing Antigravity App — ./scripts/fetch-apps.sh"

info "Starting Antigravity App 2.0 (CLOUD_CODE_URL=http://127.0.0.1:${PROXY_PORT})..."
exec_in_instance "$RT" "$INSTANCE_NAME" antigravity-app "$@"
