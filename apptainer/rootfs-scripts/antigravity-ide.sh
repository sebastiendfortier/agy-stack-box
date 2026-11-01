#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
# Keep Singularity --home (real login home) for file pickers / Open Folder.

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gui-session.sh
source "$_here/gui-session.sh"
agy_prepare_gui_session

BIN="$(agy-resolve-app ide)"
exec "$BIN" --disable-gpu-sandbox --no-sandbox "$@"
