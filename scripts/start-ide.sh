#!/usr/bin/env bash
# Launch Antigravity IDE inside the running private-net instance.
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

info "Starting Antigravity IDE (CLOUD_CODE_URL=http://127.0.0.1:${PROXY_PORT})..."
exec_in_instance "$RT" "$INSTANCE_NAME" antigravity-ide "$@"
