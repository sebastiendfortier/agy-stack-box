#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
# Keep Singularity --home (real login home) so file pickers see the user's files.
# Stack gemini/config is bind-mounted onto $HOME/.gemini from state/.
exec "$(agy-resolve-app agy)" "$@"
