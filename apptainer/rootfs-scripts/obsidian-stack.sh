#!/usr/bin/env bash
# Launch Obsidian AppImage against a vault directory (first arg).
set -euo pipefail
VAULT="${1:-${VAULT_PATH:-/vault}}"
export HOME="${HOME:-${AGY_STATE:-/agy-state}/home}"
APPIMAGE="/opt/obsidian/Obsidian.AppImage"
[[ -x "$APPIMAGE" ]] || { echo "missing $APPIMAGE" >&2; exit 1; }
# AppImage often needs extract-and-run inside containers without FUSE.
export APPIMAGE_EXTRACT_AND_RUN=1
exec "$APPIMAGE" --no-sandbox "$VAULT"
