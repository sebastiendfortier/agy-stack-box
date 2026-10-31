#!/usr/bin/env bash
set -euo pipefail
VAULT="${1:-${VAULT_PATH:-/vault}}"
export HOME="${HOME:-${AGY_STATE:-/agy-state}/home}"
APPIMAGE="$(agy-resolve-app obsidian)"
export APPIMAGE_EXTRACT_AND_RUN=1
exec "$APPIMAGE" --no-sandbox "$VAULT"
