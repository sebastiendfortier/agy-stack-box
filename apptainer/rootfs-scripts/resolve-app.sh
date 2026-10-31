#!/usr/bin/env bash
# Resolve large apps from $AGY_STATE/apps (preferred) or legacy /opt paths.
set -euo pipefail
STATE="${AGY_STATE:-/agy-state}"
name="$1"
case "$name" in
  ide)
    for c in \
      "$STATE/apps/antigravity-ide/Antigravity IDE/antigravity-ide" \
      "/opt/antigravity-ide/Antigravity IDE/antigravity-ide"; do
      if [[ -x "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  ide-dir)
    for c in \
      "$STATE/apps/antigravity-ide/Antigravity IDE" \
      "/opt/antigravity-ide/Antigravity IDE"; do
      if [[ -d "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  app)
    for c in \
      "$STATE/apps/antigravity-app/Antigravity-x64/antigravity" \
      "/opt/antigravity-app/Antigravity-x64/antigravity"; do
      if [[ -x "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  app-dir)
    for c in \
      "$STATE/apps/antigravity-app/Antigravity-x64" \
      "/opt/antigravity-app/Antigravity-x64"; do
      if [[ -d "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  agy)
    for c in "$STATE/apps/agy/agy" /opt/agy/bin/agy; do
      if [[ -x "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  obsidian)
    for c in "$STATE/apps/obsidian/Obsidian.AppImage" /opt/obsidian/Obsidian.AppImage; do
      if [[ -x "$c" ]]; then echo "$c"; exit 0; fi
    done
    ;;
  *)
    echo "unknown app: $name" >&2
    exit 2
    ;;
esac
echo "missing $name — run ./scripts/fetch-apps.sh on the host" >&2
exit 1
