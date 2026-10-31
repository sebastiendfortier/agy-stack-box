#!/usr/bin/env bash
# Launch agy CLI inside the running private-net instance.
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

# Default to OpenRouter Auto unless the caller already chose a model.
has_model=0
for arg in "$@"; do
  case "$arg" in
    --model|--model=*) has_model=1 ;;
  esac
done
if [[ $has_model -eq 0 ]]; then
  set -- --model custom-openrouter-auto "$@"
fi

exec_in_instance "$RT" "$INSTANCE_NAME" agy "$@"
