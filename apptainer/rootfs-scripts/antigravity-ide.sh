#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
# Keep Singularity --home (real login home) for file pickers / Open Folder.

# Session D-Bus: without one, libnotify autolaunch blocks ~25s per notification
# (org.freedesktop.Notifications timeout) and freezes the UI. A bare session bus
# makes notification calls fail fast instead (no daemon = instant error).
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  _dbus_sock="/tmp/agy-dbus-$UID/session.socket"
  mkdir -p "${_dbus_sock%/*}" 2>/dev/null || true
  if [[ -S "$_dbus_sock" ]] && ! dbus-send --address="unix:path=$_dbus_sock" \
      --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.Hello >/dev/null 2>&1; then
    rm -f "$_dbus_sock"   # stale socket from a dead daemon
  fi
  if [[ ! -S "$_dbus_sock" ]]; then
    dbus-daemon --session --fork --address="unix:path=$_dbus_sock" 2>/dev/null || true
  fi
  if [[ -S "$_dbus_sock" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$_dbus_sock"
  fi
fi
BIN="$(agy-resolve-app ide)"
APP="$(agy-resolve-app ide-dir)"
if [[ -u "$APP/chrome-sandbox" ]]; then
  exec "$BIN" "$@"
fi
export ELECTRON_DISABLE_SANDBOX=1
exec "$BIN" --disable-gpu-sandbox --no-sandbox "$@"
