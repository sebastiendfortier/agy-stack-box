#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
# Google OAuth (Continue with Google) uses a browser + loopback callback (~2 min).
export BROWSER="${BROWSER:-firefox}"
# Avoid libsecret/dbus hangs inside Singularity for Chromium password store.
export ELECTRON_PASSWORD_STORE="${ELECTRON_PASSWORD_STORE:-basic}"

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gui-session.sh
source "$_here/gui-session.sh"
agy_prepare_gui_session

BIN="$(agy-resolve-app app)"
exec "$BIN" --disable-gpu-sandbox --no-sandbox --password-store=basic "$@"
