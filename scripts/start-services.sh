#!/usr/bin/env bash
# Compat: ensure instance + proxy + Obsidian (prefer agy-ide / agy-cli / agy-app).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
load_secrets
ensure_services
