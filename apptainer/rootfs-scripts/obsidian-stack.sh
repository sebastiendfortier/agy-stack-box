#!/usr/bin/env bash
set -euo pipefail
# Prefer the host-path vault (same inode as /vault) so Obsidian's UI/path match the bind.
VAULT="${1:-${VAULT_HOST_PATH:-${VAULT_PATH:-/vault}}}"
# Keep Singularity --home (real login home); Obsidian config is bind-mounted from state/.
APPIMAGE="$(agy-resolve-app obsidian)"
export APPIMAGE_EXTRACT_AND_RUN=1
# If the host path is not mounted (older instance), fall back to /vault.
if [[ ! -d "$VAULT" && -d "${VAULT_PATH:-/vault}" ]]; then
  VAULT="${VAULT_PATH:-/vault}"
fi
exec "$APPIMAGE" --no-sandbox "$VAULT"
