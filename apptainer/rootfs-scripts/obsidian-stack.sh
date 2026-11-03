#!/usr/bin/env bash
set -euo pipefail
# Prefer the host-path vault (same inode as /vault) so Obsidian's UI/path match the bind.
VAULT="${1:-${VAULT_HOST_PATH:-${VAULT_PATH:-/vault}}}"
# Keep Singularity --home (real login home); Obsidian config is bind-mounted from state/.
APPIMAGE="$(agy-resolve-app obsidian)"
# If the host path is not mounted (older instance), fall back to /vault.
if [[ ! -d "$VAULT" && -d "${VAULT_PATH:-/vault}" ]]; then
  VAULT="${VAULT_PATH:-/vault}"
fi

# The AppImage runtime's EXTRACT_AND_RUN mode shares one /tmp extraction dir per
# AppImage path and deletes it on exit. A late cleanup from a previous instance
# then removes files under a starting one (FATAL V8 snapshot / ICU data errors),
# and the pidfile holds the runtime parent, so killing it orphans the window.
# Extract once into a private tree instead; later launches exec it directly.
EXTRACT_ROOT="${AGY_OBSIDIAN_EXTRACT:-${AGY_STATE:-/agy-state}/apps/obsidian-extracted}"
APP_RUN="$EXTRACT_ROOT/squashfs-root/AppRun"
STAMP="$(stat -c '%s %Y' "$APPIMAGE" 2>/dev/null || echo unknown)"

if [[ "$(cat "$EXTRACT_ROOT/.stamp" 2>/dev/null || true)" != "$STAMP" ]]; then
  mkdir -p "$EXTRACT_ROOT"
  (
    # Serialize extraction: a second launcher would otherwise race the first.
    flock -x 9
    [[ "$(cat "$EXTRACT_ROOT/.stamp" 2>/dev/null || true)" == "$STAMP" ]] && exit 0
    echo "extracting $APPIMAGE (first run for this image only)..." >&2
    tmp="$EXTRACT_ROOT/.extract.$$"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    if ( cd "$tmp" && "$APPIMAGE" --appimage-extract >/dev/null 2>&1 ); then
      rm -rf "$EXTRACT_ROOT/squashfs-root"
      mv "$tmp/squashfs-root" "$EXTRACT_ROOT/squashfs-root"
      printf '%s\n' "$STAMP" >"$EXTRACT_ROOT/.stamp"
    fi
    rm -rf "$tmp"
  ) 9>"$EXTRACT_ROOT/.extract.lock"
fi

if [[ -x "$APP_RUN" ]]; then
  exec "$APP_RUN" --no-sandbox "$VAULT"
fi

# Fallback: shared /tmp extraction (old behaviour) if the private tree is unusable.
export APPIMAGE_EXTRACT_AND_RUN=1
exec "$APPIMAGE" --no-sandbox "$VAULT"
