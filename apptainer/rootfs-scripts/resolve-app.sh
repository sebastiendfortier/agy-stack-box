#!/usr/bin/env bash
# Resolve apps baked into the SIF. Prefer the current /apps layout; retain
# /opt fallback for images built before the container layout changed.
set -euo pipefail
name="$1"
case "$name" in
  ide)
    candidates=(
      "/apps/antigravity-ide/Antigravity IDE/antigravity-ide"
      "/opt/antigravity-ide/Antigravity IDE/antigravity-ide"
    )
    ;;
  app)
    candidates=(
      "/apps/antigravity-app/Antigravity-x64/antigravity"
      "/opt/antigravity-app/Antigravity-x64/antigravity"
    )
    ;;
  agy)
    candidates=(/apps/agy/bin/agy /opt/agy/bin/agy)
    ;;
  obsidian)
    candidates=(/apps/obsidian/Obsidian.AppImage /opt/obsidian/Obsidian.AppImage)
    ;;
  *)
    echo "unknown app: $name" >&2
    exit 2
    ;;
esac

for candidate in "${candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
done

echo "missing $name — expected baked into the SIF under /apps or /opt" >&2
exit 1
