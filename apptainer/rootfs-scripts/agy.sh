#!/usr/bin/env bash
set -euo pipefail
export CLOUD_CODE_URL="${CLOUD_CODE_URL:-http://127.0.0.1:50999}"
export HOME="${HOME:-${AGY_STATE:-/agy-state}/home}"
exec "$(agy-resolve-app agy)" "$@"
