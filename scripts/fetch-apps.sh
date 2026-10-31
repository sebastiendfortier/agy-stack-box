#!/usr/bin/env bash
# Download large apps into state/apps (kept out of the SIF to stay slim).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ANTIGRAVITY_IDE_URL="${ANTIGRAVITY_IDE_URL:-https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.6.0-5526304964083712/linux-x64/Antigravity%20IDE.tar.gz}"
# Antigravity App 2.0 (multi-agent desktop — not the IDE). Pin via ANTIGRAVITY_APP_URL.
ANTIGRAVITY_APP_URL="${ANTIGRAVITY_APP_URL:-https://storage.googleapis.com/antigravity-public/antigravity-hub/2.28.2-5937220255875072/linux-x64/Antigravity.tar.gz}"
OBSIDIAN_APPIMAGE_URL="${OBSIDIAN_APPIMAGE_URL:-https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.5/Obsidian-1.14.5.AppImage}"

mkdir -p "$STATE_DIR/apps"/{antigravity-ide,antigravity-app,agy,obsidian,tmp}
chmod 700 "$STATE_DIR/apps"

need() {
  local path="$1" label="$2"
  if [[ -e "$path" ]]; then
    info "have $label"
    return 1
  fi
  return 0
}

if need "$STATE_DIR/apps/antigravity-ide/Antigravity IDE/antigravity-ide" "Antigravity IDE"; then
  info "Fetching Antigravity IDE..."
  curl -fL "$ANTIGRAVITY_IDE_URL" -o "$STATE_DIR/apps/tmp/ide.tar.gz"
  tar -xzf "$STATE_DIR/apps/tmp/ide.tar.gz" -C "$STATE_DIR/apps/antigravity-ide"
  rm -f "$STATE_DIR/apps/tmp/ide.tar.gz"
  chmod 4755 "$STATE_DIR/apps/antigravity-ide/Antigravity IDE/chrome-sandbox" 2>/dev/null || true
fi

if need "$STATE_DIR/apps/antigravity-app/Antigravity-x64/antigravity" "Antigravity App 2.0"; then
  info "Fetching Antigravity App 2.0..."
  curl -fL "$ANTIGRAVITY_APP_URL" -o "$STATE_DIR/apps/tmp/app.tar.gz"
  tar -xzf "$STATE_DIR/apps/tmp/app.tar.gz" -C "$STATE_DIR/apps/antigravity-app"
  rm -f "$STATE_DIR/apps/tmp/app.tar.gz"
  chmod 4755 "$STATE_DIR/apps/antigravity-app/Antigravity-x64/chrome-sandbox" 2>/dev/null || true
  [[ -x "$STATE_DIR/apps/antigravity-app/Antigravity-x64/antigravity" ]] \
    || die "Antigravity App extract failed (expected Antigravity-x64/antigravity)"
fi

if need "$STATE_DIR/apps/agy/agy" "agy CLI"; then
  info "Fetching agy CLI..."
  # Official installer drops into ~/.local/bin; redirect HOME into apps tree.
  OLDHOME="${HOME:-}"
  export HOME="$STATE_DIR/apps/tmp/agy-home"
  mkdir -p "$HOME"
  curl -fsSL https://antigravity.google/cli/install.sh -o "$STATE_DIR/apps/tmp/agy-install.sh"
  bash "$STATE_DIR/apps/tmp/agy-install.sh" || true
  for cand in "$HOME/.local/bin/agy" "$HOME/.gemini/bin/agy"; do
    if [[ -x "$cand" ]]; then
      cp -a "$cand" "$STATE_DIR/apps/agy/agy"
      break
    fi
  done
  export HOME="$OLDHOME"
  rm -rf "$STATE_DIR/apps/tmp/agy-home" "$STATE_DIR/apps/tmp/agy-install.sh"
  [[ -x "$STATE_DIR/apps/agy/agy" ]] || die "agy CLI install failed"
  chmod 755 "$STATE_DIR/apps/agy/agy"
fi

if need "$STATE_DIR/apps/obsidian/Obsidian.AppImage" "Obsidian AppImage"; then
  info "Fetching Obsidian..."
  curl -fL "$OBSIDIAN_APPIMAGE_URL" -o "$STATE_DIR/apps/obsidian/Obsidian.AppImage"
  chmod 755 "$STATE_DIR/apps/obsidian/Obsidian.AppImage"
fi

rmdir "$STATE_DIR/apps/tmp" 2>/dev/null || rm -rf "$STATE_DIR/apps/tmp"
info "Apps ready under $STATE_DIR/apps"
du -sh "$STATE_DIR/apps"/* 2>/dev/null || true
